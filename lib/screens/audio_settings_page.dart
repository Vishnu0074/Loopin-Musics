import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/audio_settings.dart';
import '../services/audio_settings_service.dart';
import '../services/audio_service.dart';
import '../theme/app_theme.dart';

class AudioSettingsPage extends StatefulWidget {
  const AudioSettingsPage({super.key});
  @override
  State<AudioSettingsPage> createState() => _AudioSettingsPageState();
}

class _AudioSettingsPageState extends State<AudioSettingsPage> {
  AudioSettings s = const AudioSettings();
  bool loading = true;
  final _svc = AudioSettingsService();

  static const _defaultBands = {
    '60': 0.0,
    '230': 0.0,
    '910': 0.0,
    '3600': 0.0,
    '14000': 0.0,
  };

  static const List<({String key, String label, String role})> _bandMetadata = [
    (key: '60', label: '60 Hz', role: 'SUB'),
    (key: '230', label: '230 Hz', role: 'BASS'),
    (key: '910', label: '910 Hz', role: 'MID'),
    (key: '3600', label: '3.6 kHz', role: 'PRESENCE'),
    (key: '14000', label: '14 kHz', role: 'AIR'),
  ];

  static const Map<String, ({String description, Map<String, double> bands})> _presets = {
    'Flat': (
      description: 'Studio flat response with no colorization',
      bands: _defaultBands,
    ),
    'Bass Mood': (
      description: 'Deeper low end and enhanced sub-bass presence',
      bands: {'60': 7.0, '230': 4.5, '910': 0.0, '3600': -1.0, '14000': 1.5},
    ),
    'Lo-fi Glow': (
      description: 'Soft, warm, slightly dark with rolled-off highs',
      bands: {'60': 2.5, '230': 4.5, '910': 0.5, '3600': -2.5, '14000': -5.0},
    ),
    'Night Drive': (
      description: 'Punchy bass + brighter highs for immersive drive sessions',
      bands: {'60': 5.5, '230': 3.0, '910': -1.5, '3600': 2.5, '14000': 4.5},
    ),
    'Dream Haze': (
      description: 'Atmospheric, soft mids and airy shimmer',
      bands: {'60': 2.0, '230': 2.5, '910': -2.5, '3600': 2.0, '14000': 5.5},
    ),
    'Vocal Air': (
      description: 'Clearer vocals and extended high-end clarity',
      bands: {'60': -3.0, '230': -1.5, '910': 3.5, '3600': 5.5, '14000': 4.0},
    ),
    'Deep Focus': (
      description: 'Balanced, non-fatiguing sound for long listening',
      bands: {'60': 2.5, '230': 1.5, '910': 1.0, '3600': -1.0, '14000': -3.0},
    ),
    'Cinematic Pulse': (
      description: 'Powerful low end + spacious air and dynamic scale',
      bands: {'60': 6.5, '230': 2.0, '910': -2.5, '3600': 2.5, '14000': 4.5},
    ),
    'Acoustic Glow': (
      description: 'Presence, string detail, and natural vocal warmth',
      bands: {'60': -1.0, '230': 1.0, '910': 3.0, '3600': 4.5, '14000': 3.5},
    ),
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final v = await _svc.load();
    if (mounted) {
      setState(() {
        s = v;
        loading = false;
      });
    }
  }

  Future<void> _save(AudioSettings v) async {
    setState(() => s = v);
    await _svc.save(v);
    await GlobalAudioService().applyAudioSettings(v);
  }

  String _activePreset(Map<String, double> bands) {
    for (final entry in _presets.entries) {
      if (_sameBands(entry.value.bands, bands)) return entry.key;
    }
    return 'Custom';
  }

  bool _sameBands(Map<String, double> a, Map<String, double> b) {
    for (final key in _defaultBands.keys) {
      if (((a[key] ?? 0) - (b[key] ?? 0)).abs() > .05) return false;
    }
    return true;
  }

  void _resetFlat() {
    HapticFeedback.mediumImpact();
    _save(s.copyWith(
      equalizerEnabled: true,
      equalizerBands: Map<String, double>.from(_defaultBands),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.accent)),
      );
    }

    final bands = s.equalizerBands.isEmpty ? _defaultBands : s.equalizerBands;
    final preset = _activePreset(bands);
    final activePresetData = _presets[preset];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('Equalizer & Audio', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        centerTitle: false,
        actions: [
          if (s.equalizerEnabled)
            TextButton.icon(
              onPressed: _resetFlat,
              icon: const Icon(Icons.refresh_rounded, size: 16, color: AppColors.muted),
              label: const Text('Reset', style: TextStyle(color: AppColors.muted, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              // Visual Curve Display
              _buildVisualEqCurve(bands, s.equalizerEnabled),
              const SizedBox(height: 20),

              // Master Equalizer Switch Card
              _buildMasterEqCard(preset, activePresetData?.description),
              const SizedBox(height: 20),

              // Presets Carousel
              if (s.equalizerEnabled) ...[
                _buildPresetSelector(preset),
                const SizedBox(height: 20),

                // Studio 5-Band Vertical Slider Console
                _buildStudioFaderConsole(bands),
                const SizedBox(height: 24),
              ],

              // Stereo Balance & Spatial Audio Section
              _buildStereoBalanceSection(),
              const SizedBox(height: 24),

              // Streaming Quality Section
              _buildQualitySection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVisualEqCurve(Map<String, double> bands, bool enabled) {
    final values = _bandMetadata.map((m) => bands[m.key] ?? 0.0).toList();

    return Container(
      height: 150,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.divider),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _EqCurvePainter(
                  values: values,
                  enabled: enabled,
                  accentColor: AppColors.accent,
                  gridColor: Colors.white10,
                ),
              ),
            ),
            Positioned(
              top: 12,
              left: 16,
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: enabled ? AppColors.accent : AppColors.muted,
                      shape: BoxShape.circle,
                      boxShadow: enabled
                          ? [
                              BoxShadow(
                                color: AppColors.accent.withValues(alpha: 0.6),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    enabled ? 'FREQUENCY SPECTRUM' : 'EQUALIZER BYPASSED',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: enabled ? AppColors.accent : AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 12,
              right: 16,
              child: Text(
                '+12 dB / -12 dB',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.3),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMasterEqCard(String preset, String? description) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: s.equalizerEnabled
                  ? AppColors.accent.withValues(alpha: 0.15)
                  : AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.tune_rounded,
              color: s.equalizerEnabled ? AppColors.accent : AppColors.muted,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Equalizer',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.text),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: s.equalizerEnabled ? AppColors.accent.withValues(alpha: 0.15) : AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        s.equalizerEnabled ? preset : 'Off',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: s.equalizerEnabled ? AppColors.accent : AppColors.muted,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  s.equalizerEnabled && description != null
                      ? description
                      : 'Apply acoustic tuning to the audio session',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
          Switch(
            value: s.equalizerEnabled,
            activeTrackColor: AppColors.accent,
            onChanged: (v) {
              HapticFeedback.selectionClick();
              _save(s.copyWith(equalizerEnabled: v));
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPresetSelector(String activePreset) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'EQ PROFILES & MOODS',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: AppColors.muted),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: _presets.keys.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final name = _presets.keys.elementAt(index);
              final isSelected = activePreset == name;

              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  HapticFeedback.selectionClick();
                  _save(s.copyWith(
                    equalizerEnabled: true,
                    equalizerBands: Map<String, double>.from(_presets[name]!.bands),
                  ));
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.accent.withValues(alpha: 0.18) : AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? AppColors.accent.withValues(alpha: 0.5) : AppColors.divider,
                      width: isSelected ? 1.2 : 1.0,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      name,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                        color: isSelected ? AppColors.accent : AppColors.text,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStudioFaderConsole(Map<String, double> bands) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 18, 10, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: _bandMetadata.map((meta) {
              final gain = (bands[meta.key] ?? 0.0).clamp(-12.0, 12.0);
              final isNonZero = gain.abs() > 0.1;

              return SizedBox(
                width: 58,
                child: Column(
                  children: [
                    // Gain Readout
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: isNonZero ? AppColors.accent.withValues(alpha: 0.15) : AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${gain > 0 ? "+" : ""}${gain.toStringAsFixed(1)}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: isNonZero ? AppColors.accent : AppColors.muted,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Vertical Slider Fader
                    SizedBox(
                      height: 170,
                      child: RotatedBox(
                        quarterTurns: 3,
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3.5,
                            activeTrackColor: isNonZero ? AppColors.accent : AppColors.muted,
                            inactiveTrackColor: AppColors.surfaceElevated,
                            thumbColor: AppColors.text,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                            overlayColor: AppColors.accent.withValues(alpha: 0.15),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                          ),
                          child: Slider(
                            min: -12.0,
                            max: 12.0,
                            value: gain,
                            onChanged: (v) {
                              setState(() {
                                s = s.copyWith(equalizerBands: {...bands, meta.key: v});
                              });
                              _save(s.copyWith(equalizerBands: {...bands, meta.key: v}));
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Band Frequency & Role
                    Text(
                      meta.label,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meta.role,
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildStereoBalanceSection() {
    final balance = s.balance.clamp(-1.0, 1.0);
    final isCentered = balance.abs() < 0.05;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.spatial_audio_off_rounded, size: 18, color: AppColors.accent),
                  SizedBox(width: 8),
                  Text(
                    'STEREO PAN & BALANCE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: isCentered
                    ? null
                    : () {
                        HapticFeedback.selectionClick();
                        _save(s.copyWith(balance: 0.0));
                      },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isCentered ? AppColors.surfaceElevated : AppColors.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isCentered ? 'Centered' : 'Reset Center',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isCentered ? AppColors.muted : AppColors.accent,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Balance Readout Gauge
          Center(
            child: Text(
              isCentered
                  ? 'Center (Balanced L/R)'
                  : balance < 0
                      ? 'Left Channel Bias ${(-balance * 100).round()}%'
                      : 'Right Channel Bias ${(balance * 100).round()}%',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isCentered ? AppColors.text : AppColors.accent,
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Stereo Slider with live panning
          Row(
            children: [
              const Text('L', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.muted)),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    activeTrackColor: AppColors.accent,
                    inactiveTrackColor: AppColors.surfaceElevated,
                    thumbColor: AppColors.text,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                    overlayColor: AppColors.accent.withValues(alpha: 0.15),
                  ),
                  child: Slider(
                    min: -1.0,
                    max: 1.0,
                    value: balance,
                    onChanged: (v) {
                      setState(() => s = s.copyWith(balance: v));
                      _save(s.copyWith(balance: v));
                    },
                  ),
                ),
              ),
              const Text('R', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.muted)),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: AppColors.divider, height: 1),
          const SizedBox(height: 8),

          // Mono switch
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: s.mono,
            activeTrackColor: AppColors.accent,
            onChanged: (v) {
              HapticFeedback.selectionClick();
              _save(s.copyWith(mono: v));
            },
            title: const Text('Mono Output', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text)),
            subtitle: const Text('Sum stereo channels for single earbud listening', style: TextStyle(fontSize: 12, color: AppColors.muted)),
          ),
        ],
      ),
    );
  }

  Widget _buildQualitySection() {
    const qualities = [
      (value: 'auto', title: 'Auto', subtitle: 'Dynamic adaptation'),
      (value: '96', title: '96 kbps', subtitle: 'Data saver'),
      (value: '160', title: '160 kbps', subtitle: 'Standard quality'),
      (value: '320', title: '320 kbps', subtitle: 'High fidelity stream'),
    ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.high_quality_rounded, size: 18, color: AppColors.accent),
              SizedBox(width: 8),
              Text(
                'STREAMING AUDIO BITRATE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                  color: AppColors.muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...qualities.map((q) {
            final isSelected = s.quality == q.value;

            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.accent.withValues(alpha: 0.1) : AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? AppColors.accent.withValues(alpha: 0.4) : AppColors.divider,
                ),
              ),
              child: ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                onTap: () {
                  HapticFeedback.selectionClick();
                  _save(s.copyWith(quality: q.value));
                },
                leading: Icon(
                  isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  color: isSelected ? AppColors.accent : AppColors.muted,
                  size: 20,
                ),
                title: Text(
                  q.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: isSelected ? AppColors.text : AppColors.muted,
                  ),
                ),
                subtitle: Text(
                  q.subtitle,
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
                trailing: isSelected
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('ACTIVE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.accent)),
                      )
                    : null,
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _EqCurvePainter extends CustomPainter {
  final List<double> values;
  final bool enabled;
  final Color accentColor;
  final Color gridColor;

  _EqCurvePainter({
    required this.values,
    required this.enabled,
    required this.accentColor,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1.0;

    // Draw horizontal grid lines (+12, +6, 0, -6, -12)
    final zeroY = size.height * 0.5;
    final topY = size.height * 0.15;
    final bottomY = size.height * 0.85;

    canvas.drawLine(Offset(0, topY), Offset(size.width, topY), gridPaint);
    canvas.drawLine(Offset(0, zeroY), Offset(size.width, zeroY), gridPaint..strokeWidth = 1.2);
    canvas.drawLine(Offset(0, bottomY), Offset(size.width, bottomY), gridPaint);

    final points = <Offset>[];
    final paddingX = size.width * 0.1;
    final usableWidth = size.width - (paddingX * 2);

    for (var i = 0; i < values.length; i++) {
      final x = paddingX + (i * usableWidth / (values.length - 1));
      final gain = enabled ? values[i].clamp(-12.0, 12.0) : 0.0;
      // Map gain [-12, 12] to [bottomY, topY]
      final y = zeroY - (gain / 12.0) * (zeroY - topY);
      points.add(Offset(x, y));
    }

    if (points.isEmpty) return;

    // Build smooth Bezier path through points
    final path = Path();
    path.moveTo(0, points.first.dy);
    path.lineTo(points.first.dx, points.first.dy);

    for (var i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final cx = (p0.dx + p1.dx) / 2;
      path.cubicTo(cx, p0.dy, cx, p1.dy, p1.dx, p1.dy);
    }
    path.lineTo(size.width, points.last.dy);

    // Gradient fill under the curve
    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: enabled
            ? [
                accentColor.withValues(alpha: 0.25),
                accentColor.withValues(alpha: 0.0),
              ]
            : [
                Colors.white.withValues(alpha: 0.05),
                Colors.transparent,
              ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawPath(fillPath, fillPaint);

    // Stroke line
    final linePaint = Paint()
      ..color = enabled ? accentColor : Colors.white24
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    if (enabled) {
      // Draw glow shadow
      final glowPaint = Paint()
        ..color = accentColor.withValues(alpha: 0.4)
        ..strokeWidth = 6.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawPath(path, glowPaint);
    }

    canvas.drawPath(path, linePaint);

    // Draw anchor dots on points
    for (final pt in points) {
      final dotPaint = Paint()
        ..color = enabled ? accentColor : Colors.white38
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pt, 4.0, dotPaint);

      final outerDot = Paint()
        ..color = AppColors.background
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(pt, 4.0, outerDot);
    }
  }

  @override
  bool shouldRepaint(covariant _EqCurvePainter oldDelegate) {
    return oldDelegate.enabled != enabled ||
        oldDelegate.values != values ||
        oldDelegate.accentColor != accentColor;
  }
}
