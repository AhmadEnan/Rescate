import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/providers/app_state.dart';
import '../../settings/screens/settings_screen.dart';

class TopBar extends StatelessWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const _RescateMark(),
          const Spacer(),
          const _NotificationButton(),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
            child: Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(
                color: AppColors.cardBackground,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                LucideIcons.settings,
                size: 20,
                color: AppColors.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RescateMark extends StatelessWidget {
  const _RescateMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: const BoxDecoration(
        color: AppColors.primaryRed,
        shape: BoxShape.circle,
      ),
      child: const Icon(LucideIcons.radio, color: Colors.white, size: 22),
    );
  }
}

class _NotificationButton extends StatefulWidget {
  const _NotificationButton();

  @override
  State<_NotificationButton> createState() => _NotificationButtonState();
}

class _NotificationButtonState extends State<_NotificationButton> {
  final GlobalKey _key = GlobalKey();
  OverlayEntry? _overlayEntry;
  bool _isOpen = false;

  final Stream<Map<String, String>> _notificationStream = Stream.periodic(
    const Duration(seconds: 15),
    (count) => {
      'title_en': 'Emergency Update #${count + 1}',
      'title_ar': 'تحديث حالة الطوارئ #${count + 1}',
      'body_en': 'New safe zones available near your location.',
      'body_ar': 'مناطق آمنة جديدة متاحة بالقرب من موقعك.',
      'time_en': 'Just now',
      'time_ar': 'الآن',
    },
  ).asBroadcastStream();

  Map<String, String> _currentNotification = {
    'title_en': 'Emergency Update',
    'title_ar': 'تحديث حالة الطوارئ',
    'body_en': 'Please check the map for the latest safe zone details.',
    'body_ar':
        'يُرجى التحقق من الخريطة للحصول على تفاصيل أحدث حول المناطق الآمنة.',
    'time_en': '2 mins ago',
    'time_ar': 'منذ دقيقتين',
  };

  @override
  void initState() {
    super.initState();
    _notificationStream.listen((data) {
      if (mounted) {
        setState(() {
          _currentNotification = data;
        });
        if (_isOpen && _overlayEntry != null) {
          _overlayEntry!.markNeedsBuild();
        }
      }
    });
  }

  void _toggleDropdown() {
    if (_isOpen) {
      _closeDropdown();
    } else {
      _showDropdown();
    }
  }

  void _closeDropdown() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    setState(() => _isOpen = false);
  }

  void _showDropdown() {
    final RenderBox renderBox =
        _key.currentContext!.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);

    _overlayEntry = OverlayEntry(
      builder: (context) {
        final appState = AppStateProvider.of(context);
        final isArabic = appState.isArabic;

        return Stack(
          children: [
            // Invisible barrier to catch taps outside
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _closeDropdown,
                child: Container(color: Colors.transparent),
              ),
            ),
            Positioned(
              top: offset.dy + renderBox.size.height + 8,
              right: 16, // Fixed to the right edge
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: 280,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.cardBackground,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      ),
                    ],
                    border: Border.all(
                      color: AppColors.textDark.withOpacity(0.05),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            isArabic ? 'الإشعارات' : 'Notifications',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textDark,
                            ),
                          ),
                          Icon(
                            LucideIcons.moreHorizontal,
                            size: 18,
                            color: AppColors.textDark.withOpacity(0.5),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Mock notification item
                      GestureDetector(
                        onTap: () {
                          _closeDropdown();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                isArabic
                                    ? 'فتح الإشعار...'
                                    : 'Opening notification...',
                              ),
                            ),
                          );
                        },
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: AppColors.primaryRed.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                LucideIcons.alertCircle,
                                color: AppColors.primaryRed,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isArabic
                                        ? _currentNotification['title_ar']!
                                        : _currentNotification['title_en']!,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.textDark,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    isArabic
                                        ? _currentNotification['body_ar']!
                                        : _currentNotification['body_en']!,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textDark.withOpacity(
                                        0.7,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    isArabic
                                        ? _currentNotification['time_ar']!
                                        : _currentNotification['time_en']!,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: AppColors.primaryRed,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context).insert(_overlayEntry!);
    setState(() => _isOpen = true);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: _key,
      onTap: _toggleDropdown,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              shape: BoxShape.circle,
              border: _isOpen
                  ? Border.all(color: AppColors.primaryRed, width: 1.5)
                  : null,
            ),
            child: const Icon(
              LucideIcons.bell,
              size: 20,
              color: AppColors.textDark,
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: Container(
              width: 11,
              height: 11,
              decoration: const BoxDecoration(
                color: AppColors.primaryRed,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
