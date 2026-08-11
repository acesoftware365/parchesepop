import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_language.dart';

const _reportNavy = Color(0xFF17284D);
const _reportBlue = Color(0xFF2474E5);
const _reportCloud = Color(0xFFF4F7FC);
const _reportMuted = Color(0xFF667085);

enum PlayerReportReason {
  inappropriateName(
    'Nombre inapropiado',
    'Nombre ofensivo, sexual, amenazante o que incumple las reglas.',
    Icons.badge_rounded,
    true,
  ),
  gameTampering(
    'Trampa o alteración del juego',
    'Resultado imposible, manipulación, desconexiones sospechosas o abuso del juego.',
    Icons.gavel_rounded,
    true,
  ),
  harassment(
    'Acoso o mensajes inapropiados',
    'Acoso, amenazas o uso indebido de los mensajes rápidos.',
    Icons.chat_bubble_rounded,
    true,
  ),
  technicalIssue(
    'Problema técnico u otro',
    'Error de la aplicación, partida rota o cualquier otro problema.',
    Icons.bug_report_rounded,
    false,
  );

  const PlayerReportReason(
    this.label,
    this.description,
    this.icon,
    this.requiresPlayerName,
  );

  final String label;
  final String description;
  final IconData icon;
  final bool requiresPlayerName;
}

class PlayerReportDeviceContext {
  const PlayerReportDeviceContext({
    required this.appVersion,
    required this.operatingSystem,
    required this.device,
  });

  final String appVersion;
  final String operatingSystem;
  final String device;

  static const unknown = PlayerReportDeviceContext(
    appVersion: 'Desconocida',
    operatingSystem: 'Desconocido',
    device: 'Desconocido',
  );
}

String buildPlayerReportEmail({
  required PlayerReportReason reason,
  required String playerName,
  required String description,
  required PlayerReportDeviceContext deviceContext,
  String? modeLabel,
}) {
  final trimmedName = playerName.trim();
  final trimmedDescription = description.trim();
  return '''Hola equipo de Parchís Pop,

Quiero reportar un problema dentro del juego.

Motivo: ${reason.label}
Jugador reportado: ${trimmedName.isEmpty ? 'No indicado' : trimmedName}
Versión de la app: ${deviceContext.appVersion}
Sistema operativo: ${deviceContext.operatingSystem}
Dispositivo: ${deviceContext.device}
${modeLabel == null || modeLabel.trim().isEmpty ? '' : 'Modo: ${modeLabel.trim()}\n'}
Descripción adicional:
${trimmedDescription.isEmpty ? 'No se añadió una descripción adicional.' : trimmedDescription}

No incluyo contraseñas ni información sensible.
''';
}

Uri buildPlayerReportMailto({
  required PlayerReportReason reason,
  required String playerName,
  required String description,
  required PlayerReportDeviceContext deviceContext,
  String? modeLabel,
}) {
  final body = buildPlayerReportEmail(
    reason: reason,
    playerName: playerName,
    description: description,
    deviceContext: deviceContext,
    modeLabel: modeLabel,
  );
  return Uri(
    scheme: 'mailto',
    path: 'sales@liisgo.com',
    queryParameters: {
      'subject': 'Reporte Parchís Pop · ${reason.label}',
      'body': body,
    },
  );
}

class ReportIssueScreen extends StatefulWidget {
  const ReportIssueScreen({
    super.key,
    this.initialPlayerName,
    this.suggestedPlayerNames = const <String>[],
    this.modeLabel,
  });

  final String? initialPlayerName;
  final List<String> suggestedPlayerNames;
  final String? modeLabel;

  @override
  State<ReportIssueScreen> createState() => _ReportIssueScreenState();
}

class _ReportIssueScreenState extends State<ReportIssueScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _playerController;
  late final TextEditingController _descriptionController;
  PlayerReportReason _reason = PlayerReportReason.inappropriateName;
  PlayerReportDeviceContext _deviceContext = PlayerReportDeviceContext.unknown;
  bool _loadingDeviceContext = true;
  bool _openingMail = false;
  String? _mailBody;

  @override
  void initState() {
    super.initState();
    _playerController = TextEditingController(
      text: widget.initialPlayerName?.trim() ?? '',
    );
    _descriptionController = TextEditingController();
    unawaited(_loadDeviceContext());
  }

  @override
  void dispose() {
    _playerController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadDeviceContext() async {
    try {
      final package = await PackageInfo.fromPlatform();
      final info = await DeviceInfoPlugin().deviceInfo;
      final data = info.data;
      final version = _firstValue(<Object?>[
        if (kIsWeb) data['appVersion'],
        data['systemVersion'],
        data['osRelease'],
        _nestedValue(data['version'], 'release'),
        data['displayVersion'],
        data['version'],
      ]);
      final model = _firstValue(<Object?>[
        data['modelName'],
        data['model'],
        data['productName'],
        data['prettyName'],
        data['platform'],
        data['name'],
      ]);
      if (!mounted) return;
      setState(() {
        _deviceContext = PlayerReportDeviceContext(
          appVersion: _joinVersion(package.version, package.buildNumber),
          operatingSystem:
              '${_platformLabel()}${version == 'Desconocida' ? '' : ' $version'}',
          device: model,
        );
        _loadingDeviceContext = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingDeviceContext = false);
    }
  }

  static Object? _nestedValue(Object? value, String key) {
    if (value is Map) return value[key];
    return null;
  }

  static String _firstValue(Iterable<Object?> values) {
    for (final value in values) {
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return 'Desconocida';
  }

  static String _joinVersion(String version, String build) {
    final cleanVersion = version.trim().isEmpty
        ? 'Desconocida'
        : version.trim();
    final cleanBuild = build.trim();
    return cleanBuild.isEmpty ? cleanVersion : '$cleanVersion+$cleanBuild';
  }

  static String _platformLabel() => switch (defaultTargetPlatform) {
    TargetPlatform.android => 'Android',
    TargetPlatform.iOS => 'iOS',
    TargetPlatform.macOS => 'macOS',
    TargetPlatform.windows => 'Windows',
    TargetPlatform.linux => 'Linux',
    TargetPlatform.fuchsia => 'Fuchsia',
  };

  void _useSuggestedPlayer(String name) {
    _playerController
      ..text = name
      ..selection = TextSelection.collapsed(offset: name.length);
    setState(() {});
  }

  Future<void> _openEmail() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final uri = buildPlayerReportMailto(
      reason: _reason,
      playerName: _playerController.text,
      description: _descriptionController.text,
      deviceContext: _deviceContext,
      modeLabel: widget.modeLabel,
    );
    final body = buildPlayerReportEmail(
      reason: _reason,
      playerName: _playerController.text,
      description: _descriptionController.text,
      deviceContext: _deviceContext,
      modeLabel: widget.modeLabel,
    );
    setState(() {
      _openingMail = true;
      _mailBody = body;
    });
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;
    setState(() => _openingMail = false);
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: PopText(
            'No se pudo abrir una aplicación de correo. Puedes copiar el reporte.',
          ),
        ),
      );
    }
  }

  Future<void> _copyReport() async {
    final body = _mailBody;
    if (body == null) return;
    await Clipboard.setData(ClipboardData(text: body));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: PopText('Reporte copiado.')));
  }

  InputDecoration _inputDecoration(String label, {String? hint}) =>
      InputDecoration(
        labelText: appTranslate(context, label),
        hintText: hint == null ? null : appTranslate(context, hint),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFDDE3EF)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFDDE3EF)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _reportBlue, width: 2),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const PopText('Reportar jugador o problema')),
    backgroundColor: _reportCloud,
    body: Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _reportNavy,
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.flag_rounded, color: Colors.white, size: 30),
                SizedBox(width: 12),
                Expanded(
                  child: PopText(
                    'Ayúdanos a mantener Parchís Pop seguro y justo. El reporte abre un correo preparado; tú decides si lo envías.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          PopText(
            '¿Qué quieres reportar?',
            style: const TextStyle(
              color: _reportNavy,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<PlayerReportReason>(
            initialValue: _reason,
            decoration: _inputDecoration('Motivo del reporte'),
            items: [
              for (final reason in PlayerReportReason.values)
                DropdownMenuItem(
                  value: reason,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(reason.icon, color: _reportBlue, size: 20),
                      const SizedBox(width: 9),
                      PopText(reason.label),
                    ],
                  ),
                ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _reason = value);
            },
          ),
          const SizedBox(height: 7),
          PopText(
            _reason.description,
            style: const TextStyle(
              color: _reportMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          TextFormField(
            controller: _playerController,
            textInputAction: TextInputAction.next,
            decoration: _inputDecoration(
              'Nombre del jugador reportado',
              hint: 'Escribe el nombre tal como aparece en la partida',
            ),
            validator: (value) {
              if (_reason.requiresPlayerName &&
                  (value == null || value.trim().isEmpty)) {
                return appTranslate(context, 'Escribe el nombre del jugador.');
              }
              return null;
            },
          ),
          if (widget.suggestedPlayerNames.isNotEmpty) ...[
            const SizedBox(height: 8),
            PopText(
              'Jugadores de esta partida',
              style: const TextStyle(
                color: _reportMuted,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final name in widget.suggestedPlayerNames)
                  ActionChip(
                    label: PopText(name),
                    onPressed: () => _useSuggestedPlayer(name),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          TextFormField(
            controller: _descriptionController,
            textCapitalization: TextCapitalization.sentences,
            maxLines: 5,
            maxLength: 1000,
            decoration: _inputDecoration(
              'Comentario adicional (opcional)',
              hint: 'Cuéntanos qué ocurrió, cuándo pasó y qué viste.',
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFDDE3EF)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PopText(
                  'Información incluida automáticamente',
                  style: TextStyle(
                    color: _reportNavy,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                _ReportContextLine(
                  icon: Icons.new_releases_rounded,
                  label: 'Versión de la app',
                  value: _deviceContext.appVersion,
                ),
                _ReportContextLine(
                  icon: Icons.phone_android_rounded,
                  label: 'Sistema operativo',
                  value: _deviceContext.operatingSystem,
                ),
                _ReportContextLine(
                  icon: Icons.devices_rounded,
                  label: 'Dispositivo',
                  value: _deviceContext.device,
                ),
                if (_loadingDeviceContext)
                  const Padding(
                    padding: EdgeInsets.only(top: 5),
                    child: PopText(
                      'Preparando información del dispositivo…',
                      style: TextStyle(
                        color: _reportMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            key: const ValueKey('report-open-email'),
            onPressed: _openingMail ? null : _openEmail,
            icon: _openingMail
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.email_rounded),
            label: const PopText('Preparar correo a sales@liisgo.com'),
            style: FilledButton.styleFrom(
              backgroundColor: _reportBlue,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
          if (_mailBody != null) ...[
            const SizedBox(height: 9),
            OutlinedButton.icon(
              key: const ValueKey('report-copy-fallback'),
              onPressed: _copyReport,
              icon: const Icon(Icons.copy_rounded),
              label: const PopText('Copiar reporte'),
            ),
          ],
          const SizedBox(height: 10),
          const PopText(
            'No envíes contraseñas, códigos de acceso ni otros datos sensibles.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _reportMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}

class _ReportContextLine extends StatelessWidget {
  const _ReportContextLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: _reportBlue, size: 17),
        const SizedBox(width: 8),
        Expanded(
          child: PopText(
            '$label: $value',
            style: const TextStyle(
              color: _reportNavy,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}
