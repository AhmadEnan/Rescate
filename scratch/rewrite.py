import sys

file_path = r"f:\Rescate\apps\rescate_app\lib\features\onboarding\screens\onboarding_screen.dart"

with open(file_path, "r", encoding="utf-8") as f:
    lines = f.readlines()

# We know the first 123 lines are fine. We will replace everything from line 124 to the end.
new_content = """  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final data = _pages[_currentPage];
    final isLeft = data.panel.alignment == Alignment.centerLeft;
    final isRight = data.panel.alignment == Alignment.centerRight;
    final isBottom = data.panel.alignment == Alignment.bottomCenter;

    final panelW = isBottom ? size.width : size.width * 0.5;
    final panelH = size.height * 0.5;
    const radius = 28.0;
    const borderW = 2.5;

    final isLogoTop = data.logoPosition == _LogoPosition.topCenter;
    final isLogoLeft = data.logoPosition == _LogoPosition.bottomLeft;
    final isLogoRight = data.logoPosition == _LogoPosition.bottomRight;

    return Scaffold(
      backgroundColor: _OnboardingColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            // ── Background Panel (Animated) ──
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: panelH,
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeInOutCubic,
                alignment: isBottom
                    ? Alignment.bottomCenter
                    : (isLeft ? Alignment.bottomLeft : Alignment.bottomRight),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeInOutCubic,
                  width: panelW,
                  height: panelH,
                  decoration: BoxDecoration(
                    color: data.panel.color,
                    border: Border(
                      top: BorderSide(color: data.panel.borderColor, width: borderW),
                      left: isRight || isBottom ? BorderSide(color: data.panel.borderColor, width: borderW) : BorderSide.none,
                      right: isLeft || isBottom ? BorderSide(color: data.panel.borderColor, width: borderW) : BorderSide.none,
                    ),
                    borderRadius: BorderRadius.only(
                      topLeft: isBottom || isRight ? const Radius.circular(radius) : Radius.zero,
                      topRight: isBottom || isLeft ? const Radius.circular(radius) : Radius.zero,
                    ),
                    gradient: isBottom && data.panel.colorEnd != null
                        ? LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [data.panel.color, data.panel.colorEnd!],
                          )
                        : null,
                  ),
                ),
              ),
            ),

            // ── Logo (Animated) ──
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.only(left: 32, right: 32, bottom: 36, top: 60),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeInOutCubic,
                  alignment: isLogoTop
                      ? Alignment.topCenter
                      : (isLogoLeft ? Alignment.bottomLeft : Alignment.bottomRight),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOutBack,
                    width: 64, // Bigger logo
                    height: 64,
                    child: Image.asset('assets/logo.png'),
                  ),
                ),
              ),
            ),

            // ── Page swiper (Text only now) ───────────────────────────────
            PageView.builder(
              controller: _pageController,
              onPageChanged: (p) => setState(() => _currentPage = p),
              itemCount: _pages.length,
              itemBuilder: (_, i) => _OnboardingPage(data: _pages[i], pageIndex: i),
            ),

            // ── Top progress dashes (Static) ──────────────────────────────
            Positioned(
              top: 16,
              left: 32,
              right: 32,
              child: Row(
                children: List.generate(3, (i) {
                  return Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      height: 2,
                      margin: EdgeInsets.only(right: i < 2 ? 8 : 0),
                      decoration: BoxDecoration(
                        color: _pages[_currentPage].textColor
                            .withOpacity(i == _currentPage ? 0.7 : 0.2),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Individual onboarding page ───────────────────────────────────────────────
class _OnboardingPage extends StatelessWidget {
  final _PageData data;
  final int pageIndex;
  const _OnboardingPage({required this.data, required this.pageIndex});

  @override
  Widget build(BuildContext context) {
    final isPage3 = data.logoPosition == _LogoPosition.topCenter;

    return Stack(
      children: [
        // ── Text content ─────────────────────────────────────────────────
        Positioned(
          top: isPage3 ? 160 : 70,
          left: 28,
          right: 28,
          child: Column(
            crossAxisAlignment: isPage3
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              Text(
                data.title,
                textAlign:
                    isPage3 ? TextAlign.center : TextAlign.start,
                style: GoogleFonts.poppins(
                  fontSize: 48,
                  fontWeight: FontWeight.w900,
                  color: data.textColor,
                  height: 1.05,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                data.description,
                textAlign:
                    isPage3 ? TextAlign.center : TextAlign.start,
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  color: data.textColor.withOpacity(0.75),
                  height: 1.55,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
"""

with open(file_path, "w", encoding="utf-8") as f:
    f.writelines(lines[:123])
    f.write(new_content)

print("Done")
