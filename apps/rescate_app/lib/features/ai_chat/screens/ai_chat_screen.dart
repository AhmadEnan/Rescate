import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../../../core/theme/app_colors.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../home/widgets/top_bar.dart';
import '../../../core/providers/app_state.dart';

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> with AutomaticKeepAliveClientMixin {
  final TextEditingController _controller = TextEditingController();
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = false;

  late stt.SpeechToText _speech;
  bool _isListening = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('chat_history');
    if (data != null) {
      setState(() {
        _messages = List<Map<String, dynamic>>.from(jsonDecode(data));
      });
    }
  }

  Future<void> _saveMessages() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('chat_history', jsonEncode(_messages));
  }

  void _listen() async {
    if (!_isListening) {
      try {
        bool available = await _speech.initialize(
          onError: (val) => print('onError: $val'),
          onStatus: (val) => print('onStatus: $val'),
        );
        if (available) {
          setState(() => _isListening = true);
          _speech.listen(
            onResult: (val) => setState(() {
              _controller.text = val.recognizedWords;
            }),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone not available or permission denied.')),
          );
        }
      } catch (e) {
        print('Speech initialization failed: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Speech-to-text not fully supported here. Please restart the app or use a compatible browser (like Chrome).')),
        );
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
    }
  }

  Future<void> _sendMessage() async {
    if (_controller.text.trim().isEmpty) return;
    
    final question = _controller.text.trim();
    setState(() {
      _messages.add({'text': question, 'isUser': true});
      _controller.clear();
      _isLoading = true;
      if (_isListening) {
        _isListening = false;
        _speech.stop();
      }
    });
    _saveMessages();

    try {
      final res = await http.post(
        Uri.parse('http://127.0.0.1:5000/ask'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'question': question}),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _messages.add({
            'text': data['answer'],
            'thinking': data['thinking'],
            'isUser': false,
          });
        });
        _saveMessages();
      } else {
        setState(() {
          _messages.add({'text': 'Error: Failed to fetch from AI.', 'isUser': false});
        });
        _saveMessages();
      }
    } catch (e) {
      setState(() {
        _messages.add({'text': 'Error: Cannot connect to AI server.\nMake sure the RAG server is running.', 'isUser': false});
      });
      _saveMessages();
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isArabic = AppStateProvider.of(context).isArabic;

    return Container(
      color: AppColors.background,
      child: SafeArea(
        bottom: false,
        child: Directionality(
          textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
          child: Column(
          children: [
            const TopBar(),

            // ── Chat Messages ────────────────────────────────────
            Expanded(
              child: _messages.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: const _ChatBubble(isEmpty: true, isUser: false),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final msg = _messages[index];
                        final isUser = msg['isUser'] == true;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Align(
                            alignment: isUser ? Alignment.topRight : Alignment.topLeft,
                            child: _ChatBubble(
                                text: msg['text'],
                                thinking: msg['thinking'],
                                isUser: isUser),
                          ),
                        );
                      },
                    ),
            ),

            // ── Input Bar ────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 110), // Added padding for nav bar
              child: Column(
                children: [
                  if (_isLoading)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Row(
                        children: [
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primaryRed,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isArabic ? 'الذكاء الاصطناعي يفكر...' : 'AI is thinking...',
                            style: TextStyle(fontSize: 12, color: AppColors.textDark.withValues(alpha: 0.6)),
                          ),
                        ],
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 50,
                          decoration: BoxDecoration(
                            color: AppColors.aiAccentPink.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(
                              color: AppColors.aiAccentPink,
                              width: 1.5,
                            ),
                          ),
                          child: TextField(
                            controller: _controller,
                            onSubmitted: (_) => _sendMessage(),
                            decoration: InputDecoration(
                              hintText: isArabic ? 'اكتب رسالتك...' : 'Type your message...',
                              hintStyle: const TextStyle(
                                  color: Color(0xFFB0A0A0), fontSize: 14),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: () {
                          if (_controller.text.isNotEmpty || _isLoading) {
                            if (!_isLoading) _sendMessage();
                          } else {
                            _listen();
                          }
                        },
                        child: Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: _isListening ? AppColors.primaryRed : AppColors.cardBackground,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _isLoading ? LucideIcons.loader : (_controller.text.isNotEmpty ? LucideIcons.send : LucideIcons.mic),
                            color: _isListening ? Colors.white : (_isLoading ? AppColors.textDark.withValues(alpha: 0.3) : AppColors.primaryRed), 
                            size: 20),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

class _ChatBubbleTail extends CustomPainter {
  final Color color;
  final bool isUser;
  _ChatBubbleTail(this.color, this.isUser);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path();
    if (isUser) {
      path.moveTo(0, 0); 
      path.lineTo(0, size.height); 
      path.lineTo(size.width, size.height); 
      path.close();
    } else {
      path.moveTo(size.width, 0);
      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
      path.close();
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ChatBubble extends StatelessWidget {
  final String? text;
  final String? thinking;
  final bool isEmpty;
  final bool isUser;

  const _ChatBubble({this.text, this.thinking, this.isEmpty = false, this.isUser = true});

  @override
  Widget build(BuildContext context) {
    final color = isUser ? AppColors.primaryRed : AppColors.cardBackground;
    final textColor = isUser ? Colors.white : AppColors.textDark;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (!isUser)
          CustomPaint(
            size: const Size(12, 16),
            painter: _ChatBubbleTail(color, false),
          ),
        Container(
          width: isEmpty ? 220 : null,
          height: isEmpty ? 140 : null,
          constraints:
              isEmpty ? null : const BoxConstraints(maxWidth: 260),
          padding: isEmpty
              ? EdgeInsets.zero
              : const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomRight: Radius.circular(isUser ? 0 : 18),
              bottomLeft: Radius.circular(isUser ? 18 : 0),
            ),
          ),
          child: isEmpty
              ? null
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (thinking != null && thinking!.isNotEmpty) ...[
                      Text(thinking!,
                          style: TextStyle(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                              color: textColor.withValues(alpha: 0.7))),
                      const SizedBox(height: 8),
                      Container(
                        height: 1,
                        color: textColor.withValues(alpha: 0.2),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Text(text ?? '',
                        style: TextStyle(
                            fontSize: 14, color: textColor)),
                  ],
                ),
        ),
        if (isUser)
          CustomPaint(
            size: const Size(12, 16),
            painter: _ChatBubbleTail(color, true),
          ),
      ],
    );
  }
}