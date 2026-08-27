import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_language.dart';

/// Shared navigation header for the non-game screens.
///
/// Game boards retain their compact match controls, while hubs, help and
/// account pages use this centered title treatment.
class PopStandardAppBar extends StatelessWidget implements PreferredSizeWidget {
  const PopStandardAppBar({
    super.key,
    required this.title,
    this.backButtonKey,
    this.onBack,
    this.actions = const [],
  });

  static const navy = Color(0xFF17284D);

  final String title;
  final Key? backButtonKey;
  final VoidCallback? onBack;
  final List<Widget> actions;

  @override
  Size get preferredSize => const Size.fromHeight(72);

  @override
  Widget build(BuildContext context) => AppBar(
    backgroundColor: navy,
    foregroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
    systemOverlayStyle: SystemUiOverlayStyle.light,
    elevation: 0,
    scrolledUnderElevation: 0,
    toolbarHeight: preferredSize.height,
    centerTitle: true,
    leading: IconButton(
      key: backButtonKey,
      tooltip: appTranslate(context, 'Volver'),
      onPressed: onBack ?? () => Navigator.maybePop(context),
      icon: const Icon(Icons.arrow_back_rounded),
    ),
    title: PopText(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 25,
        fontWeight: FontWeight.w900,
      ),
    ),
    actions: actions,
  );
}
