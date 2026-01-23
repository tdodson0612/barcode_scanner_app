// tutorial_overlay.dart
import 'package:flutter/material.dart';

enum TutorialStep {
  TUTORIAL_INTRO,
  TUTORIAL_SCAN,
  TUTORIAL_AUTO,
  TUTORIAL_MANUAL,
  TUTORIAL_LOOKUP,
  TUTORIAL_UNIFIED_RESULT,
  TUTORIAL_CLOSE,
}

class TutorialOverlay extends StatefulWidget {
  final VoidCallback onComplete;
  final GlobalKey autoButtonKey;
  final GlobalKey scanButtonKey;
  final GlobalKey manualButtonKey;
  final GlobalKey lookupButtonKey;

  const TutorialOverlay({
    Key? key,
    required this.onComplete,
    required this.autoButtonKey,
    required this.scanButtonKey,
    required this.manualButtonKey,
    required this.lookupButtonKey,
  }) : super(key: key);

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay>
    with SingleTickerProviderStateMixin {
  TutorialStep _currentStep = TutorialStep.TUTORIAL_INTRO;
  late AnimationController _leviController;
  late Animation<Offset> _leviSlideAnimation;
  
  bool _showHighlight = false;
  GlobalKey? _currentHighlightKey;
  
  @override
  void initState() {
    super.initState();
    
    // Levi slide-in animation
    _leviController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    
    _leviSlideAnimation = Tween<Offset>(
      begin: const Offset(1.5, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _leviController,
      curve: Curves.easeOut,
    ));
    
    // Start Levi's entrance
    _leviController.forward();
  }
  
  @override
  void dispose() {
    _leviController.dispose();
    super.dispose();
  }
  
  void _nextStep() {
    setState(() {
      switch (_currentStep) {
        case TutorialStep.TUTORIAL_INTRO:
          _currentStep = TutorialStep.TUTORIAL_SCAN;
          _updateHighlight(widget.scanButtonKey);
          break;
        case TutorialStep.TUTORIAL_SCAN:
          _currentStep = TutorialStep.TUTORIAL_AUTO;
          _updateHighlight(widget.autoButtonKey);
          break;
        case TutorialStep.TUTORIAL_AUTO:
          _currentStep = TutorialStep.TUTORIAL_MANUAL;
          _updateHighlight(widget.manualButtonKey);
          break;
        case TutorialStep.TUTORIAL_MANUAL:
          _currentStep = TutorialStep.TUTORIAL_LOOKUP;
          _updateHighlight(widget.lookupButtonKey);
          break;
        case TutorialStep.TUTORIAL_LOOKUP:
          _currentStep = TutorialStep.TUTORIAL_UNIFIED_RESULT;
          _removeHighlight();
          break;
        case TutorialStep.TUTORIAL_UNIFIED_RESULT:
          _currentStep = TutorialStep.TUTORIAL_CLOSE;
          break;
        case TutorialStep.TUTORIAL_CLOSE:
          widget.onComplete();
          break;
      }
    });
  }
  
  void _updateHighlight(GlobalKey newKey) async {
    // Fade out previous highlight
    setState(() => _showHighlight = false);
    await Future.delayed(const Duration(milliseconds: 100));
    
    // Fade in new highlight
    setState(() {
      _currentHighlightKey = newKey;
      _showHighlight = true;
    });
  }
  
  void _removeHighlight() async {
    setState(() => _showHighlight = false);
    await Future.delayed(const Duration(milliseconds: 100));
    setState(() => _currentHighlightKey = null);
  }
  
  String _getTalkBubbleText() {
    switch (_currentStep) {
      case TutorialStep.TUTORIAL_INTRO:
        return "Hi there, friend. I am Levi, the liver. Let me walk you through this app and the way we use it to enrich our health and our lives.";
      case TutorialStep.TUTORIAL_SCAN:
        return "Let's start with Scan. Tap this when you want to scan a barcode yourself. You'll take a picture, tap Analyze, and we'll show you the nutrition facts and helpful recipe ideas.";
      case TutorialStep.TUTORIAL_AUTO:
        return "This one is Auto. It works just like Scan, but faster. Just point your camera at the barcode, and it recognizes it automatically.";
      case TutorialStep.TUTORIAL_MANUAL:
        return "Use Manual when a barcode won't scan or is damaged. You can type in the numbers from the bottom of the barcode instead.";
      case TutorialStep.TUTORIAL_LOOKUP:
        return "And this is Lookup. Tap here to search by name if you don't have a barcode at all.";
      case TutorialStep.TUTORIAL_UNIFIED_RESULT:
        return "No matter which option you choose, you'll see nutrition facts and recipe suggestions for that item. Pick what works best for you.";
      case TutorialStep.TUTORIAL_CLOSE:
        return "That's it! I'll be here if you need help. Let's take care of your health together.";
    }
  }
  
  Widget _buildHighlight() {
    if (_currentHighlightKey == null) return const SizedBox.shrink();
    
    final RenderBox? renderBox = _currentHighlightKey!.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return const SizedBox.shrink();
    
    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    
    return AnimatedOpacity(
      opacity: _showHighlight ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: Positioned(
        left: position.dx - 8,
        top: position.dy - 8,
        child: Container(
          width: size.width + 16,
          height: size.height + 16,
          decoration: BoxDecoration(
            border: Border.all(
              color: Colors.yellow,
              width: 3,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(0.7),
      child: GestureDetector(
        onTap: _nextStep,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            // Yellow highlight
            _buildHighlight(),
            
            // Levi character (bottom-right)
            Positioned(
              right: 16,
              bottom: 140,
              child: SlideTransition(
                position: _leviSlideAnimation,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.asset(
                      'assets/leviliver.png',
                      width: 120,
                      height: 120,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ),
            
            // Talk bubble
            Positioned(
              left: 16,
              right: 152,
              bottom: 180,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Text(
                  _getTalkBubbleText(),
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black87,
                    height: 1.4,
                  ),
                ),
              ),
            ),
            
            // Tap to continue
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Tap to continue',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            
            // X button (top-right)
            Positioned(
              top: 48,
              right: 16,
              child: GestureDetector(
                onTap: widget.onComplete,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.close,
                    color: Colors.black87,
                    size: 24,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}