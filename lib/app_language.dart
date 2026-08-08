import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as material show Text;
import 'package:shared_preferences/shared_preferences.dart';

enum AppLanguagePreference { system, spanish, english }

extension AppLanguagePreferenceValue on AppLanguagePreference {
  String get storedValue => switch (this) {
    AppLanguagePreference.system => 'system',
    AppLanguagePreference.spanish => 'es',
    AppLanguagePreference.english => 'en',
  };

  static AppLanguagePreference fromStored(String? value) => switch (value) {
    'es' => AppLanguagePreference.spanish,
    'en' => AppLanguagePreference.english,
    _ => AppLanguagePreference.system,
  };
}

class AppLanguageController extends ChangeNotifier with WidgetsBindingObserver {
  AppLanguageController() {
    WidgetsBinding.instance.addObserver(this);
  }

  static const preferenceKey = 'settings_language';
  AppLanguagePreference _preference = AppLanguagePreference.system;

  AppLanguagePreference get preference => _preference;
  String get preferenceCode => _preference.storedValue;

  Locale? get localeOverride => switch (_preference) {
    AppLanguagePreference.system => null,
    AppLanguagePreference.spanish => const Locale('es'),
    AppLanguagePreference.english => const Locale('en'),
  };

  String get effectiveLanguageCode {
    if (_preference == AppLanguagePreference.spanish) return 'es';
    if (_preference == AppLanguagePreference.english) return 'en';
    final systemLanguage =
        WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    if (systemLanguage == 'es' || systemLanguage == 'en') {
      return systemLanguage;
    }
    return 'es';
  }

  Future<void> initialize() async {
    final store = await SharedPreferences.getInstance();
    final saved = store.getString(preferenceKey);
    _preference = AppLanguagePreferenceValue.fromStored(saved);
    if (saved != 'system' && saved != 'es' && saved != 'en') {
      await store.setString(preferenceKey, 'system');
    }
    notifyListeners();
  }

  Future<void> select(AppLanguagePreference preference) async {
    if (_preference != preference) {
      _preference = preference;
      notifyListeners();
    }
    final store = await SharedPreferences.getInstance();
    await store.setString(preferenceKey, preference.storedValue);
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    if (_preference == AppLanguagePreference.system) notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

class AppLanguageScope extends InheritedNotifier<AppLanguageController> {
  const AppLanguageScope({
    super.key,
    required AppLanguageController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppLanguageController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppLanguageScope>()?.notifier;
}

String appLanguageCodeOf(BuildContext context) =>
    AppLanguageScope.maybeOf(context)?.effectiveLanguageCode ?? 'es';

String appTranslate(BuildContext context, String source) =>
    translateForLanguage(source, appLanguageCodeOf(context));

const _legacyPrivacyDescription =
    'El prototipo guarda localmente el perfil, las monedas, las compras cosméticas y las preferencias. Antes de publicar se documentarán el servicio de cuenta, analíticas, publicidad y cualquier dato que salga del dispositivo.';
const _privacyDescription =
    'La aplicación guarda localmente el perfil, las monedas, las compras cosméticas y las preferencias. Si activas la analítica anónima, Google Analytics recopila eventos de partidas, reanudación, tutorial, anuncios voluntarios, monedas y tienda para mejorar el juego. No enviamos el nombre, el correo, los mensajes, la bandera ni el avatar.';

String translateForLanguage(String source, String languageCode) {
  if (source == _legacyPrivacyDescription) source = _privacyDescription;
  if (languageCode != 'en' || source.isEmpty) return source;
  final exact = _english[source];
  if (exact != null) return exact;
  return _translateDynamic(source);
}

String _translateDynamic(String source) {
  final patterns = <(RegExp, String Function(Match))>[
    (
      RegExp(r'^¡Hola, (.+)! (.+)$'),
      (match) => 'Hi, ${match.group(1)}! ${match.group(2)}',
    ),
    (
      RegExp(r'^Preparando partida local · (\d+)s$'),
      (match) => 'Preparing local match · ${match.group(1)}s',
    ),
    (
      RegExp(r'^Añadiendo CPU · (\d+)/(\d+)$'),
      (match) => 'Adding CPU players · ${match.group(1)}/${match.group(2)}',
    ),
    (
      RegExp(r'^Parchís Pop · (Caos|Tradicional|Quick Pop)$'),
      (match) => 'Parchís Pop · ${translateForLanguage(match.group(1)!, 'en')}',
    ),
    (
      RegExp(r'^(Quick Pop|Tutorial) • CPU (Fácil|Normal|Experto)$'),
      (match) =>
          '${match.group(1)} • CPU ${translateForLanguage(match.group(2)!, 'en')}',
    ),
    (
      RegExp(r'^¡Duplicaste tu premio: \+(\d+) monedas!$'),
      (match) => 'You doubled your reward: +${match.group(1)} coins!',
    ),
    (
      RegExp(r'^\+(\d+) MONEDAS POR JUGAR$'),
      (match) => '+${match.group(1)} COINS FOR PLAYING',
    ),
    (
      RegExp(r'^VER ANUNCIO · DUPLICAR\n\+(\d+) MONEDAS$'),
      (match) => 'WATCH AD · DOUBLE\n+${match.group(1)} COINS',
    ),
    (
      RegExp(r'^\+(\d+) MONEDAS DUPLICADAS$'),
      (match) => '+${match.group(1)} DOUBLED COINS',
    ),
    (
      RegExp(r'^Tus (dos|cuatro) fichas llegaron a la meta\.$'),
      (match) =>
          'Your ${match.group(1) == 'dos' ? 'two' : 'four'} pieces reached home.',
    ),
    (
      RegExp(r'^Rivales listos · (.+)$'),
      (match) => 'Opponents ready · ${match.group(1)}',
    ),
    (
      RegExp(r'^Completando la mesa · (.+)$'),
      (match) => 'Completing the table · ${match.group(1)}',
    ),
    (
      RegExp(r'^Nivel (\d+) · (.+)$'),
      (match) =>
          'Level ${match.group(1)} · ${_translateCompoundLabel(match.group(2)!)}',
    ),
    (
      RegExp(r'^(.+) Nv\. (\d+) · (.+)$'),
      (match) =>
          '${match.group(1)} Lv. ${match.group(2)} · ${_translateCompoundLabel(match.group(3)!)}',
    ),
    (RegExp(r'^Nivel (\d+)$'), (match) => 'Level ${match.group(1)}'),
    (RegExp(r'^Nv\. (\d+)$'), (match) => 'Lv. ${match.group(1)}'),
    (RegExp(r'^COMPRAR · 🪙 (.+)$'), (match) => 'BUY · 🪙 ${match.group(1)}'),
    (
      RegExp(r'^¡(.+) comprado y equipado!$'),
      (match) =>
          '${translateForLanguage(match.group(1)!, 'en')} purchased and equipped!',
    ),
    (
      RegExp(r'^(.+) está en uso\.$'),
      (match) => '${translateForLanguage(match.group(1)!, 'en')} is equipped.',
    ),
    (
      RegExp(r'^(.+) NIVEL (\d+)$'),
      (match) => '${match.group(1)} LEVEL ${match.group(2)}',
    ),
    (
      RegExp(r'^Sacaste (\d+) y (\d+)\.$'),
      (match) => 'You rolled ${match.group(1)} and ${match.group(2)}.',
    ),
    (
      RegExp(r'^(.+) sacó (\d+) y (\d+)\.$'),
      (match) =>
          '${match.group(1)} rolled ${match.group(2)} and ${match.group(3)}.',
    ),
    (
      RegExp(r'^Elige (\d+) o (\d+)$'),
      (match) => 'Choose ${match.group(1)} or ${match.group(2)}',
    ),
    (
      RegExp(r'^Comenzó la partida en modo (Caos|Tradicional)\.$'),
      (match) =>
          'The ${match.group(1) == 'Caos' ? 'Chaos' : 'Traditional'} match started.',
    ),
    (
      RegExp(r'^Comenzó el turno de (.+)\.$'),
      (match) => "${match.group(1)}'s turn started.",
    ),
    (
      RegExp(r'^Turno (\d+) · #(\d+)$'),
      (match) => 'Turn ${match.group(1)} · #${match.group(2)}',
    ),
    (
      RegExp(r'^(.+) sacó la ficha (\d+) de la cárcel\.$'),
      (match) => '${match.group(1)} moved piece ${match.group(2)} out.',
    ),
    (
      RegExp(r'^(.+) movió la ficha (\d+) (\d+) pasos\.$'),
      (match) =>
          '${match.group(1)} moved piece ${match.group(2)} ${match.group(3)} spaces.',
    ),
    (
      RegExp(
        r'^(.+) usó todos los dados \((\d+) \+ (\d+)\) con la ficha (\d+) y avanzó (\d+) pasos\.$',
      ),
      (match) =>
          '${match.group(1)} used both dice (${match.group(2)} + ${match.group(3)}) with piece ${match.group(4)} and moved ${match.group(5)} spaces.',
    ),
    (
      RegExp(r'^(.+) abrió su barrera al mover la ficha (\d+)\.$'),
      (match) =>
          '${match.group(1)} opened their barrier by moving piece ${match.group(2)}.',
    ),
    (
      RegExp(r'^(.+) formó una barrera con las fichas (.+)\.$'),
      (match) =>
          '${match.group(1)} formed a barrier with pieces ${match.group(2)}.',
    ),
    (
      RegExp(r'^(.+) capturó la ficha (\d+) de (.+)\.$'),
      (match) =>
          '${match.group(1)} captured ${match.group(3)}’s piece ${match.group(2)}.',
    ),
    (
      RegExp(
        r'^Tres dobles: la ficha (\d+) de (.+) volvió a la cárcel\.( La barrera se abrió\.)?$',
      ),
      (match) =>
          'Three doubles: ${match.group(2)}’s piece ${match.group(1)} returned to base.'
          '${match.group(3) == null ? '' : ' The barrier opened.'}',
    ),
    (
      RegExp(r'^Tres dobles: no había una ficha en juego para penalizar\.$'),
      (match) => 'Three doubles: there was no piece in play to penalize.',
    ),
    (
      RegExp(r'^(.+) llevó la ficha (\d+) a la meta\.$'),
      (match) =>
          '${match.group(1)} brought piece ${match.group(2)} to the goal.',
    ),
    (
      RegExp(r'^(.+) llevó la ficha (\d+) a la meta con Turbo\.$'),
      (match) =>
          '${match.group(1)} brought piece ${match.group(2)} to the goal with Turbo.',
    ),
    (
      RegExp(r'^(.+) usó Turbo con la ficha (\d+) y avanzó (\d+) pasos\.$'),
      (match) =>
          '${match.group(1)} used Turbo on piece ${match.group(2)} and moved ${match.group(3)} spaces.',
    ),
    (
      RegExp(r'^La trampa (.+) de (.+) fue bloqueada por el escudo de (.+)\.$'),
      (match) =>
          '${match.group(2)}’s ${translateForLanguage(match.group(1)!, 'en')} trap was blocked by ${match.group(3)}’s Shield.',
    ),
    (RegExp(r'^Turno de (.+)\.$'), (match) => "${match.group(1)}'s turn."),
    (
      RegExp(r'^(.+) sacó dobles\. ¡Tira otra vez!$'),
      (match) => '${match.group(1)} rolled doubles. Roll again!',
    ),
    (
      RegExp(r'^(.+) no tiene movimientos\.$'),
      (match) => '${match.group(1)} has no legal moves.',
    ),
    (
      RegExp(r'^(.+) sacó una ficha\.$'),
      (match) => '${match.group(1)} moved a piece out.',
    ),
    (
      RegExp(r'^Avanzaste (\d+)\.$'),
      (match) => 'You moved ${match.group(1)} spaces.',
    ),
    (
      RegExp(r'^Avanzaste (\d+) usando ambos dados\.$'),
      (match) => 'You moved ${match.group(1)} spaces using both dice.',
    ),
    (
      RegExp(r'^(.+) avanzó (\d+)\.$'),
      (match) => '${match.group(1)} moved ${match.group(2)} spaces.',
    ),
    (
      RegExp(r'^(.+) avanzó (\d+) usando ambos dados\.$'),
      (match) =>
          '${match.group(1)} moved ${match.group(2)} spaces using both dice.',
    ),
    (
      RegExp(
        r'^(.+) Bono \+20: cada color muestra dónde puede caer tu ficha\.$',
      ),
      (match) =>
          '${translateForLanguage(match.group(1)!, 'en')} +20 bonus: each color shows where that piece can land.',
    ),
    (
      RegExp(r'^(.+) (.+) ganó un bono de 20 pasos\.$'),
      (match) =>
          '${translateForLanguage(match.group(1)!, 'en')} ${match.group(2)} earned a 20-space bonus.',
    ),
    (
      RegExp(r'^¡(.+) llevó una ficha a casa!$'),
      (match) => '${match.group(1)} brought a piece home!',
    ),
    (
      RegExp(r'^¡(.+) capturó una ficha!$'),
      (match) => '${match.group(1)} captured a piece!',
    ),
    (
      RegExp(r'^¡(.+) despejó su entrada!$'),
      (match) => '${match.group(1)} cleared their entrance!',
    ),
    (
      RegExp(r'^El escudo de (.+) bloqueó la captura\.$'),
      (match) => "${match.group(1)}'s Shield blocked the capture.",
    ),
    (
      RegExp(r'^(.+) ganó la partida!$'),
      (match) => '${match.group(1)} won the game!',
    ),
    (RegExp(r'^(.+) GANA$'), (match) => '${match.group(1)} WINS'),
    (
      RegExp(
        r'^(.+) llevó sus (dos|cuatro) fichas a la meta\. ¡La revancha está lista!$',
      ),
      (match) =>
          '${match.group(1)} brought ${match.group(2) == 'dos' ? 'both pieces' : 'all four pieces'} home. The rematch is ready!',
    ),
    (
      RegExp(r'^(.+) (perdió|perdieron) su turno por el pegamento\. (.+)$'),
      (match) =>
          '${match.group(1)} ${match.group(2) == 'perdió' ? 'lost a turn' : 'lost their turns'} because of Glue. ${translateForLanguage(match.group(3)!, 'en')}',
    ),
    (
      RegExp(r'^(\d+) dados disponibles$'),
      (match) => '${match.group(1)} dice available',
    ),
    (
      RegExp(r'^Dado (\d+) disponible$'),
      (match) => 'Die ${match.group(1)} available',
    ),
    (RegExp(r'^Dado (\d+) usado$'), (match) => 'Die ${match.group(1)} used'),
    (
      RegExp(r'^F(\d+): mira dónde cae con \+20$'),
      (match) => 'P${match.group(1)}: preview the +20 landing',
    ),
    (
      RegExp(r'^Elige un dado o TODOS \((\d+)\)$'),
      (match) => 'Choose one die or ALL (${match.group(1)})',
    ),
    (
      RegExp(r'^FICHA (\d+) · (.+)$'),
      (match) =>
          'PIECE ${match.group(1)} · ${translateForLanguage(match.group(2)!, 'en')}',
    ),
    (RegExp(r'^Comprar · ([\d,]+)$'), (match) => 'Buy · ${match.group(1)}'),
    (RegExp(r'^Comprar (.+)$'), (match) => 'Buy ${match.group(1)}'),
    (
      RegExp(r'^Añadiste ([\d,]+) monedas de prueba\.$'),
      (match) => 'You added ${match.group(1)} test coins.',
    ),
    (RegExp(r'^\+([\d,]+) monedas$'), (match) => '+${match.group(1)} coins'),
    (
      RegExp(r'^SALDO ACTUAL · ([\d,]+)$'),
      (match) => 'CURRENT BALANCE · ${match.group(1)}',
    ),
    (
      RegExp(
        r'^Se descontarán ([\d,]+) monedas\. Los artículos de la tienda son solamente cosméticos\.$',
      ),
      (match) =>
          '${match.group(1)} coins will be deducted. Shop items are cosmetic only.',
    ),
    (
      RegExp(r'^TRAMPA PUESTA · (.+) · casilla (\d+)$'),
      (match) =>
          'TRAP SET · ${translateForLanguage(match.group(1)!, 'en')} · space ${match.group(2)}',
    ),
    (
      RegExp(r'^TRAMPA · (.+) · #(\d+)$'),
      (match) =>
          'TRAP · ${translateForLanguage(match.group(1)!, 'en')} · #${match.group(2)}',
    ),
    (
      RegExp(r'^TRAMPAS ×(\d+) · última (.+) #(\d+)$'),
      (match) =>
          'TRAPS ×${match.group(1)} · latest ${translateForLanguage(match.group(2)!, 'en')} #${match.group(3)}',
    ),
    (
      RegExp(r'^(\d+) trampas armadas$'),
      (match) => '${match.group(1)} armed traps',
    ),
    (
      RegExp(r'^(\d+) trampas ocultas$'),
      (match) => '${match.group(1)} hidden traps',
    ),
    (
      RegExp(r'^(.+) · casilla (\d+)$'),
      (match) =>
          '${translateForLanguage(match.group(1)!, 'en')} · space ${match.group(2)}',
    ),
    (RegExp(r'^casilla (\d+)$'), (match) => 'space ${match.group(1)}'),
    (
      RegExp(r'^(.+) en #(\d+)$'),
      (match) =>
          '${translateForLanguage(match.group(1)!, 'en')} on #${match.group(2)}',
    ),
    (
      RegExp(r'^(.+) oculta en la casilla (\d+)\.$'),
      (match) =>
          '${translateForLanguage(match.group(1)!, 'en')} hidden on space ${match.group(2)}.',
    ),
    (
      RegExp(r'^(PODER|TRAMPA LISTA) · (.+): (.+)$'),
      (match) =>
          '${match.group(1) == 'PODER' ? 'POWER' : 'TRAP READY'} · ${translateForLanguage(match.group(2)!, 'en')}: ${translateForLanguage(match.group(3)!, 'en')}',
    ),
    (
      RegExp(r'^(.+): (.+)$'),
      (match) =>
          '${translateForLanguage(match.group(1)!, 'en')}: ${translateForLanguage(match.group(2)!, 'en')}',
    ),
    (
      RegExp(r'^Demostración: (.+)$'),
      (match) => 'Demo: ${translateForLanguage(match.group(1)!, 'en')}',
    ),
    (
      RegExp(r'^Probar (.+)$'),
      (match) => 'Try ${translateForLanguage(match.group(1)!, 'en')}',
    ),
    (
      RegExp(r'^(Colocar|Usar):? (.+)$'),
      (match) =>
          '${match.group(1) == 'Colocar' ? 'Place' : 'Use'} ${translateForLanguage(match.group(2)!, 'en')}',
    ),
    (
      RegExp(r'^Armada: (.+)$'),
      (match) => 'Armed: ${translateForLanguage(match.group(1)!, 'en')}',
    ),
    (
      RegExp(r'^PODER · (.+) guardado$'),
      (match) =>
          'POWER · ${translateForLanguage(match.group(1)!, 'en')} stored',
    ),
    (
      RegExp(r'^TRAMPA LISTA · (.+)$'),
      (match) => 'TRAP READY · ${translateForLanguage(match.group(1)!, 'en')}',
    ),
    (
      RegExp(r'^Encontraste (.+)\. Quedó guardado\.$'),
      (match) =>
          'You found ${translateForLanguage(match.group(1)!, 'en')}. It was stored.',
    ),
    (
      RegExp(
        r'^Encontraste (.+)\. Se armó automáticamente y quedó oculta en la casilla (\d+)\.$',
      ),
      (match) =>
          'You found ${translateForLanguage(match.group(1)!, 'en')}. It armed automatically and is hidden on space ${match.group(2)}.',
    ),
    (
      RegExp(r'^(.+) encontró un objeto sorpresa y dejó una trampa oculta\.$'),
      (match) =>
          '${match.group(1)} found a surprise item and left a hidden trap.',
    ),
    (
      RegExp(r'^(.+) encontró un objeto sorpresa\.$'),
      (match) => '${match.group(1)} found a surprise item.',
    ),
    (
      RegExp(r'^Avanzaste (\d+) con Turbo\.$'),
      (match) => 'You moved ${match.group(1)} spaces with Turbo.',
    ),
    (
      RegExp(r'^(.+) avanzó (\d+) con Turbo\.$'),
      (match) => '${match.group(1)} moved ${match.group(2)} spaces with Turbo.',
    ),
    (
      RegExp(r'^Colocaste (.+) oculta en la casilla (\d+)\.$'),
      (match) =>
          'You placed a hidden ${translateForLanguage(match.group(1)!, 'en').toLowerCase()} on space ${match.group(2)}.',
    ),
    (
      RegExp(r'^(.+) colocó una trampa oculta\.$'),
      (match) => '${match.group(1)} placed a hidden trap.',
    ),
    (
      RegExp(r'^(.+) ya tiene una trampa activa\.$'),
      (match) => '${match.group(1)} already has an active trap.',
    ),
    (
      RegExp(r'^(.+) tiene un escudo automático preparado\.$'),
      (match) => '${match.group(1)} has an automatic Shield ready.',
    ),
    (
      RegExp(r'^¡Turbo llevó una ficha a casa!$'),
      (match) => 'Turbo brought a piece home!',
    ),
    (
      RegExp(r'^¡(.+) llevó una ficha a casa con Turbo!$'),
      (match) => '${match.group(1)} brought a piece home with Turbo!',
    ),
    (
      RegExp(r'^¡PEGAMENTO! (.+) perderá su próximo turno\.$'),
      (match) => 'GLUE! ${match.group(1)} will lose their next turn.',
    ),
    (
      RegExp(r'^¡RETROCESO! (.+) retrocedió (\d+) pasos\.$'),
      (match) =>
          'SETBACK! ${match.group(1)} moved back ${match.group(2)} spaces.',
    ),
    (
      RegExp(r'^¡TRAMPA CÁRCEL! (.+) volvió a la cárcel\.$'),
      (match) => 'PRISON TRAP! ${match.group(1)} returned to base.',
    ),
    (
      RegExp(r'^¡BOMBA! (.+) volvió a la cárcel\.$'),
      (match) => 'BOMB! ${match.group(1)} returned to base.',
    ),
    (
      RegExp(r'^¡PROTEGIDO! Tu escudo automático bloqueó (.+)\.$'),
      (match) =>
          'PROTECTED! Your automatic Shield blocked ${translateForLanguage(match.group(1)!, 'en')}.',
    ),
    (
      RegExp(r'^¡PROTEGIDO! El escudo de (.+) bloqueó (.+)\.$'),
      (match) =>
          'PROTECTED! ${match.group(1)}’s Shield blocked ${translateForLanguage(match.group(2)!, 'en')}.',
    ),
    (
      RegExp(r'^Secuencia (\d+) de (\d+) · (.+)$'),
      (match) =>
          'Sequence ${match.group(1)} of ${match.group(2)} · ${translateForLanguage(match.group(3)!, 'en')}',
    ),
  ];
  for (final (pattern, replacement) in patterns) {
    final match = pattern.firstMatch(source);
    if (match != null) return replacement(match);
  }
  return source;
}

String _translateCompoundLabel(String source) => source
    .split(' · ')
    .map((part) => translateForLanguage(part, 'en'))
    .join(' · ');

const _english = <String, String>{
  // Global navigation and profile.
  'Ajustes': 'Settings',
  'Volver': 'Back',
  'Volver al inicio': 'Back to home',
  'VOLVER AL INICIO': 'BACK TO HOME',
  'Volviendo al inicio…': 'Returning to home…',
  'Cerrar': 'Close',
  'Cancelar': 'Cancel',
  'Ahora no': 'Not now',
  'Continuar': 'Continue',
  'Invitado': 'Guest',
  'Perfil': 'Profile',
  'Mi perfil': 'My profile',
  'Registrarme': 'Sign up',
  'Editar perfil': 'Edit profile',
  'Edita tu perfil': 'Edit your profile',
  'Crear perfil': 'Create profile',
  'Guardar cambios': 'Save changes',
  'Crea tu perfil de jugador': 'Create your player profile',
  'Crea tu perfil para jugar online': 'Create a profile to play online',
  'Nombre de jugador': 'Player name',
  'Ej. JuanPop': 'E.g. JuanPop',
  'Correo electrónico': 'Email address',
  'Contraseña': 'Password',
  'Confirmar contraseña': 'Confirm password',
  'Contraseña actual': 'Current password',
  'Nueva contraseña': 'New password',
  'Cambiar contraseña': 'Change password',
  'Cambiar clave': 'Change password',
  'Olvidé mi clave': 'Forgot password',
  'Guardar clave': 'Save password',
  'Crear cuenta con correo': 'Create account with email',
  'Continuar con Google': 'Continue with Google',
  'Continuar con Apple': 'Continue with Apple',
  'O CONTINÚA CON': 'OR CONTINUE WITH',
  '8+ caracteres, mayúscula, minúscula y número':
      '8+ characters, uppercase, lowercase, and a number',
  'Usa 8 caracteres con mayúscula, minúscula y número.':
      'Use 8 characters with uppercase, lowercase, and a number.',
  'Las contraseñas no coinciden.': 'Passwords do not match.',
  'Escribe tu contraseña actual.': 'Enter your current password.',
  'Cuenta protegida con correo y contraseña':
      'Account protected with email and password',
  'Contraseña actualizada.': 'Password updated.',
  'Revisa tu correo para cambiar la contraseña.':
      'Check your email to change your password.',
  'La contraseña nunca se guarda como texto. Google y Apple se activarán al conectar las credenciales del servicio.':
      'Your password is never stored as plain text. Google and Apple activate when service credentials are connected.',
  'La cuenta es opcional, permanece en este dispositivo y la contraseña nunca se guarda como texto.':
      'The account is optional, stays on this device, and the password is never stored as plain text.',
  'Elige tu bandera': 'Choose your flag',
  'Usa entre 3 y 12 caracteres.': 'Use 3 to 12 characters.',
  'Usa letras, números, espacios, _ o -.':
      'Use letters, numbers, spaces, _ or -.',
  'Ese nombre no está permitido.': 'That name is not allowed.',
  'Escribe tu correo.': 'Enter your email.',
  'Escribe un correo válido.': 'Enter a valid email.',
  'El correo se guardará localmente en este prototipo. La cuenta segura y la verificación se conectarán al servicio de autenticación.':
      'Your email is stored locally in this prototype. Secure accounts and verification will connect to the authentication service.',

  // Home and game setup.
  '¡Listo para jugar!': 'Ready to play!',
  'Elige tu partida y lleva tus cuatro fichas al centro.':
      'Choose a game and race all four pieces to the center.',
  'ELIGE TU PARTIDA': 'CHOOSE YOUR GAME',
  'PARTIDA ONLINE': 'ONLINE MATCH',
  'Juega online con otros jugadores': 'Play online with other players',
  'CONTRA CPU': 'PLAY CPU',
  'Practica y domina el tablero': 'Practice and master the board',
  'Tienda': 'Shop',
  'Cómo jugar': 'How to play',
  'CÓMO JUGAR': 'HOW TO PLAY',
  'Trampas': 'Traps',
  'PUBLICIDAD': 'ADVERTISEMENT',
  'Puedes jugar contra el CPU sin registrarte. Para partidas online necesitamos un nombre y un correo para guardar tu progreso.':
      'You can play the CPU without signing up. Online games need a name and email so your progress can be saved.',
  'Elige cómo jugar': 'Choose how to play',
  'Elige las reglas para tu partida online':
      'Choose the rules for your online match',
  'Elige las reglas para tu partida rápida':
      'Choose the rules for your quick match',
  'Elige la dificultad': 'Choose difficulty',
  'Paso 1 de 2 · modo de partida': 'Step 1 of 2 · game mode',
  'Paso 2 de 2 · nivel del CPU': 'Step 2 of 2 · CPU level',
  'Volver a modos': 'Back to modes',
  'Tradicional': 'Traditional',
  'Caos': 'Chaos',
  'Reglas clásicas, sin cubos, objetos ni trampas.':
      'Classic rules with no cubes, items, or traps.',
  'Cubos sorpresa, poderes, trampas y efectos especiales.':
      'Surprise cubes, powers, traps, and special effects.',
  'CLÁSICO': 'CLASSIC',
  'MÁS ACCIÓN': 'MORE ACTION',
  'Fácil': 'Easy',
  'Normal': 'Normal',
  'Experto': 'Expert',
  'Para aprender y practicar': 'Learn and practice',
  'Una partida equilibrada': 'A balanced game',
  'El CPU calcula trampas y bloqueos': 'The CPU plans traps and blockades',
  'JUGAR': 'PLAY',
  '⚡ Modo Caos seleccionado': '⚡ Chaos Mode selected',
  '🏆 Modo Tradicional seleccionado': '🏆 Traditional Mode selected',

  // Version 2: Quick Pop, contextual tutorial, and progression.
  'MESA RÁPIDA': 'QUICK TABLE',
  'Partida local con rivales CPU': 'Local match with CPU opponents',
  'Quick Pop': 'Quick Pop',
  'Misiones': 'Missions',
  'Elige las reglas de la mesa local': 'Choose the rules for your local match',
  'CPU temporal': 'Temporary CPU',
  'CPU TEMPORAL': 'TEMPORARY CPU',
  'TUTORIAL JUGABLE': 'PLAYABLE TUTORIAL',
  '¿CÓMO QUIERES APRENDER?': 'HOW DO YOU WANT TO LEARN?',
  'Empieza una partida guiada o consulta todas las reglas.':
      'Start a guided match or review all the rules.',
  'GUÍA COMPLETA': 'COMPLETE GUIDE',
  'Aprende dentro de tu primera partida': 'Learn during your first match',
  '1 · TIRA LOS DADOS': '1 · ROLL THE DICE',
  'Toca los dados en el panel inferior.': 'Tap the dice in the bottom panel.',
  '2 · SACA UNA FICHA': '2 · RELEASE A PIECE',
  'Cuando tengas un 5, toca la ficha señalada.':
      'When you roll a 5, tap the highlighted piece.',
  '3 · ELIGE EL DESTINO': '3 · CHOOSE THE DESTINATION',
  'Toca una burbuja sobre la casilla de llegada.':
      'Tap a bubble above the destination space.',
  '4 · BUSCA UNA ESTRELLA': '4 · FIND A STAR',
  'Cae en una casilla segura marcada con estrella.':
      'Land on a safe space marked with a star.',
  '5 · CAPTURA': '5 · CAPTURE',
  'Cae sobre una ficha rival que no esté en seguro.':
      'Land on an opponent piece outside a safe space.',
  '6 · LLEGA A META': '6 · REACH HOME',
  'Completa el recorrido y entra al centro.':
      'Complete the route and enter the center.',
  'TUTORIAL LISTO': 'TUTORIAL COMPLETE',
  'Ya conoces la partida.': 'You now know how to play.',
  'YA SÉ JUGAR': 'I KNOW HOW TO PLAY',
  'Tu progreso': 'Your progress',
  'MISIONES DE HOY': "TODAY'S MISSIONS",
  'Juega normalmente; los premios llegan solos.':
      'Play normally; rewards arrive automatically.',
  'Mueve 20 casillas': 'Move 20 spaces',
  'Saca una ficha': 'Release a piece',
  'Termina una partida': 'Finish one match',
  'OBJETIVO SEMANAL': 'WEEKLY GOAL',
  'Completa partidas; ganar no es obligatorio.':
      'Complete matches; winning is not required.',
  'Termina 7 partidas': 'Finish 7 matches',
  'MONEDAS DISPONIBLES': 'AVAILABLE COINS',
  'Un tema de 1,800 se alcanza jugando varios días.':
      'A 1,800-coin theme is reachable after playing for several days.',
  'LISTO': 'DONE',
  'Premios por jugar, no por pagar': 'Rewards for playing, not paying',
  'Terminar, quedar en una posición y volver cada día entrega monedas. Los anuncios son opcionales y los cosméticos no dan ventaja.':
      'Finishing matches, placing, and returning each day earns coins. Ads are optional and cosmetics provide no advantage.',
  'Rango y eventos: protegidos': 'Ranked play and events: protected',
  'Se activarán solo cuando el servidor pueda validar dados, movimientos, resultados y recompensas sin desincronización.':
      'They will activate only when the server can validate dice, moves, results, and rewards without losing synchronization.',

  // Matchmaking and online.
  'Buscando…': 'Searching…',
  'Buscando jugadores': 'Finding players',
  'Preparando la mesa…': 'Preparing the table…',
  'Preparando rivales automáticos…': 'Preparing computer-controlled opponents…',
  'Preparando partida local': 'Preparing local match',
  'Armando tu mesa…': 'Setting up your table…',
  'Jugadores': 'Players',
  'Jugadores encontrados': 'Players found',
  'Buscamos jugadores durante 6 segundos. Si faltan asientos, los completamos automáticamente para iniciar la partida.':
      'We look for players for 6 seconds. If seats are missing, we fill them automatically to start the match.',
  'Esta partida usa rivales controlados por el juego. No requiere una cuenta ni conexión multijugador.':
      'This match uses computer-controlled opponents. It does not require an account or a multiplayer connection.',
  'Esta versión prepara la partida en tu dispositivo y completa los demás asientos con CPU.':
      'This version prepares the match on your device and fills the remaining seats with CPU players.',
  'Esta partida local está en curso. Si sales ahora, se cerrará.':
      'This local match is in progress. If you leave now, it will end.',
  'Preparando…': 'Preparing…',
  'Rival': 'Opponent',
  'Rival online': 'Online opponent',
  'Tú': 'You',
  'TÚ': 'YOU',
  'NV. 12': 'LV. 12',
  '¡La revancha está lista!': 'The rematch is ready!',

  // Game HUD and results.
  'Jugar': 'Play',
  'Reglas': 'Rules',
  'Tiempo de partida': 'Match time',
  'TIEMPO': 'TIME',
  'Historial de eventos': 'Event history',
  'Historial de la partida': 'Match history',
  'Mensajes rápidos': 'Quick messages',
  'MENSAJES RÁPIDOS': 'QUICK MESSAGES',
  'Solo frases preseleccionadas y seguras.':
      'Only reviewed, preselected phrases.',
  'Espera un momento antes de enviar otro mensaje.':
      'Wait a moment before sending another message.',
  'Más reciente primero': 'Newest first',
  'Cada acción importante queda guardada durante esta partida.':
      'Every important action is saved during this match.',
  'INICIO': 'START',
  'TURNO': 'TURN',
  'TIRADA': 'ROLL',
  'MOVIMIENTO': 'MOVE',
  'SALIDA DEL NIDO': 'LEAVE BASE',
  'BARRERA FORMADA': 'BARRIER FORMED',
  'BARRERA ABIERTA': 'BARRIER OPENED',
  'CAPTURA': 'CAPTURE',
  'TRES DOBLES': 'THREE DOUBLES',
  'SIN MOVIMIENTOS': 'NO MOVES',
  'META': 'GOAL',
  'PODER': 'POWER',
  'TRAMPA': 'TRAP',
  'VICTORIA': 'VICTORY',
  'Lanzar': 'Roll',
  'Lanza los dados': 'Roll the dice',
  'Toca los dados para lanzar.': 'Tap the dice to roll.',
  'TOCA PARA LANZAR': 'TAP TO ROLL',
  'Tu movimiento': 'Your move',
  'Selecciona un dado o revisa el tablero': 'Choose a die or inspect the board',
  'Lanza los dados o revisa el tablero': 'Roll or inspect the board',
  'Observa el turno en el tablero': 'Follow the turn on the board',
  'VISOR': 'VIEWER',
  'MINIMAPA': 'MINIMAP',
  'Visor del tablero': 'Board viewer',
  'Ficha roja': 'Red piece',
  'Ficha verde': 'Green piece',
  'Ficha amarilla': 'Yellow piece',
  'Ficha azul': 'Blue piece',
  'Arrastra el marco dorado.': 'Drag the gold frame.',
  'TABLERO COMPLETO': 'FULL BOARD',
  'Tablero completo': 'Full board',
  'Siguiendo': 'Following',
  'Vista manual': 'Manual view',
  'Vista ampliada': 'Zoomed view',
  'Toca o arrastra para ampliar una zona del tablero.':
      'Tap or drag to enlarge a board area.',
  'Mantén el dedo sobre el minimapa para ampliar y arrastra para mover la vista.':
      'Hold the minimap to zoom, then drag to move the view.',
  'MANTÉN PARA AMPLIAR': 'HOLD TO ZOOM',
  'MANTÉN Y ARRASTRA': 'HOLD AND DRAG',
  'SUELTA PARA VOLVER': 'RELEASE TO RESET',
  'AMPLIADO': 'ZOOMED',
  'Mantén el dedo y arrastra.': 'Hold and drag.',
  'Suelta para ver el tablero completo.': 'Release to see the full board.',
  'Versión del juego': 'Game version',
  '¡Tu turno! Lanza los dados.': 'Your turn! Roll the dice.',
  '¡Tu turno!': 'Your turn!',
  'Turno de Tú.': 'Your turn.',
  'Elige una ficha': 'Choose a piece',
  'Elige cuántos pasos': 'Choose the number of steps',
  'Elige una casilla blanca': 'Choose a white space',
  'Selecciona una casilla blanca para colocar la trampa.':
      'Choose a white space to place the trap.',
  'Pulsa SALIDA': 'Tap START',
  'Resolviendo el efecto…': 'Resolving effect…',
  'Resolviendo la trampa…': 'Resolving trap…',
  'BONO +20 · Elige una ficha por color': 'BONUS +20 · Choose a piece by color',
  'BONO +20': 'BONUS +20',
  '1 dado disponible': '1 die available',
  'Sin objeto': 'No item',
  'Sin poder ni trampa': 'No power or trap',
  'Sin poder · 0 trampas': 'No power · 0 traps',
  'Modo tradicional': 'Traditional mode',
  'Cancelar trampa': 'Cancel trap',
  'Objeto oculto': 'Hidden item',
  'Escudo automático': 'Automatic Shield',
  'Escudo listo · automático': 'Shield ready · automatic',
  'PODER · Escudo listo · AUTO': 'POWER · Shield ready · AUTO',
  'Poder automático oculto': 'Hidden automatic power',
  'Trampa automática': 'Automatic trap',
  '1 trampa armada': '1 armed trap',
  '1 trampa oculta': '1 hidden trap',
  'Las trampas se arman automáticamente en la casilla del cristal.':
      'Traps arm automatically on the crystal space.',
  'Escudo listo: se activará automáticamente al caer en una trampa rival.':
      'Shield ready: it activates automatically when a piece lands on a rival trap.',
  '⚡ CAOS': '⚡ CHAOS',
  '🏆 CLÁSICO': '🏆 CLASSIC',
  '🏆 TRADICIONAL': '🏆 TRADITIONAL',
  'TRADICIONAL': 'TRADITIONAL',
  'CAOS': 'CHAOS',
  'PODER ACTIVADO': 'POWER ACTIVATED',
  'TRAMPA ARMADA': 'TRAP READY',
  'TRAMPA LISTA': 'TRAP READY',
  'TRAMPA PUESTA': 'TRAP SET',
  'Poder oculto guardado': 'Hidden power stored',
  'Trampa oculta activa': 'Hidden trap active',
  'PODER · Escudo listo': 'POWER · Shield ready',
  'PODER · Escudo listo · automático': 'POWER · Shield ready · automatic',
  'Colocación de trampa cancelada.': 'Trap placement canceled.',
  'Ya tienes una trampa activa.': 'You already have an active trap.',
  'UN PODER POR JUGADOR': 'ONE POWER PER PLAYER',
  'PODER AUTOMÁTICO · TRAMPAS ACTIVAS': 'AUTOMATIC POWER · ACTIVE TRAPS',
  'PRUEBA · TRAMPAS': 'TEST · TRAPS',
  'VISTA DE PRUEBA · TODAS LAS TRAMPAS SON VISIBLES':
      'TEST VIEW · ALL TRAPS ARE VISIBLE',
  '¡Ganaste la partida!': 'You won the game!',
  '¡GANASTE!': 'YOU WON!',
  'TÚ ERES EL CAMPEÓN': 'YOU ARE THE CHAMPION',
  '¡BUENA PARTIDA!': 'GOOD GAME!',
  'CLASIFICACIÓN FINAL': 'FINAL STANDINGS',
  'PARTIDA EN PAUSA': 'MATCH PAUSED',
  'La celebración pausa la mesa. Sigue viendo para conservar esta misma partida.':
      'The celebration pauses the match. Keep watching to continue this same game.',
  'Los demás jugadores siguen compitiendo por su posición.':
      'The other players are still competing for their place.',
  'La partida terminó. Estos son los resultados.':
      'The match is over. Here are the final results.',
  'QUICK POP': 'QUICK POP',
  '2 / 2 EN META': '2 / 2 HOME',
  '4 / 4 EN META': '4 / 4 HOME',
  'PUNTOS': 'POINTS',
  'EN META': 'HOME',
  'ÚLTIMO LUGAR': 'LAST PLACE',
  'MODO ESPECTADOR': 'SPECTATOR MODE',
  'OBSERVANDO': 'WATCHING',
  'La partida continúa por los lugares restantes.':
      'The match continues for the remaining places.',
  'SALIR': 'EXIT',
  'JUGAR OTRA VEZ': 'PLAY AGAIN',
  'SEGUIR VIENDO LA PARTIDA': 'KEEP WATCHING THE MATCH',
  'Tus cuatro fichas llegaron a la meta.':
      'All four of your pieces reached home.',
  'CARGANDO ANUNCIO…': 'LOADING AD…',
  'Este premio ya estaba duplicado.': 'This reward was already doubled.',
  'No se completó el anuncio. Puedes intentarlo otra vez.':
      'The ad was not completed. You can try again.',
  'No hay un anuncio disponible ahora. Inténtalo más tarde.':
      'No ad is available right now. Try again later.',
  'No se pudo mostrar el anuncio. Tus monedas no cambiaron.':
      'The ad could not be shown. Your coin balance did not change.',
  'Sacaste dobles. ¡Tira otra vez!': 'You rolled doubles. Roll again!',
  'No tienes movimientos.': 'You have no legal moves.',
  'Tres dobles: la ficha más adelantada vuelve a la cárcel.':
      'Three doubles: your leading piece returns to base.',
  'Sacaste una ficha.': 'You moved a piece out.',
  '¡CAPTURA!': 'CAPTURE!',
  '¡Capturaste una ficha!': 'You captured a piece!',
  '¡Despejaste tu entrada y capturaste una ficha!':
      'You cleared your entrance and captured a piece!',
  '¡SALIDA!': 'START!',
  '¡SALIDA + CAPTURA!': 'START + CAPTURE!',
  '¡FICHA EN META!': 'PIECE HOME!',
  '¡Llevaste una ficha a casa!': 'You brought a piece home!',
  '¡SORPRESA!': 'SURPRISE!',
  'CAPTURAR': 'CAPTURE',
  'SALIDA': 'START',
  'PASO': 'STEP',
  'PASOS': 'STEPS',
  'TODOS': 'ALL',

  // Powers and traps.
  'Poderes y trampas': 'Powers and traps',
  'Demostración': 'Demo',
  'Escudo': 'Shield',
  'Turbo': 'Turbo',
  'Pegamento': 'Glue',
  'Retroceso': 'Setback',
  'Cárcel': 'Prison',
  'Bomba': 'Bomb',
  'Trampa pegajosa': 'Glue trap',
  'Trampa de retroceso': 'Setback trap',
  'Trampa cárcel': 'Prison trap',
  'Se activa automáticamente al caer en una trampa rival y se consume al bloquearla.':
      'Activates automatically on a rival trap and is consumed when it blocks it.',
  'Se activa solo y bloquea una trampa.':
      'Activates automatically and blocks one trap.',
  'Mueve tu ficha más adelantada hasta 3 pasos.':
      'Moves your leading piece up to 3 spaces.',
  'El rival que caiga aquí pierde su próximo turno.':
      'A rival who lands here loses their next turn.',
  'El rival que caiga aquí retrocede hasta 6 pasos.':
      'A rival who lands here moves back up to 6 spaces.',
  'El rival que caiga aquí vuelve a la cárcel.':
      'A rival who lands here returns to base.',
  'Concede movimiento adicional.': 'Grants an extra move.',
  'La ficha pierde su próximo turno.': 'The piece loses its next turn.',
  'La ficha retrocede hasta 6 pasos.': 'The piece moves back up to 6 spaces.',
  'Devuelve esa ficha a su base.': 'Returns that piece to its base.',
  'Explota y devuelve la ficha a su base.':
      'Explodes and returns the piece to its base.',
  'Explota y manda a la cárcel a la ficha rival.':
      'Explodes and sends the rival piece back to base.',
  'TURBO +3': 'TURBO +3',
  'PEGAMENTO · TURNO PERDIDO': 'GLUE · TURN LOST',
  'RETROCESO −6': 'SETBACK −6',
  '¡A LA CÁRCEL!': 'BACK TO BASE!',
  '¡BOMBA!': 'BOMB!',
  '¡PROTEGIDO!': 'PROTECTED!',
  'ESCUDO ACTIVADO': 'SHIELD ACTIVATED',
  'CAÍSTE EN PEGAMENTO': 'YOU LANDED ON GLUE',
  'CAÍSTE EN RETROCESO': 'YOU LANDED ON SETBACK',
  'CAÍSTE EN TRAMPA CÁRCEL': 'YOU LANDED ON A PRISON TRAP',
  'CAÍSTE EN UNA BOMBA': 'YOU LANDED ON A BOMB',
  'ESCUDO BLOQUEÓ': 'SHIELD BLOCKED IT',
  'ESCUDO CONSEGUIDO': 'SHIELD COLLECTED',
  'TURBO CONSEGUIDO': 'TURBO COLLECTED',
  'Efecto completado · toca para repetir': 'Effect complete · tap to replay',

  // Shop.
  'Personaliza tu juego': 'Customize your game',
  'Personaliza tu juego sin ventajas competitivas.':
      'Customize your game without competitive advantages.',
  'Destacados': 'Featured',
  'Temas': 'Themes',
  'Dados': 'Dice',
  'Fichas': 'Pieces',
  'Avatares': 'Avatars',
  'COMPRAR': 'BUY',
  'PREVIEW': 'PREVIEW',
  'VISTA PREVIA': 'PREVIEW',
  'VISTA PREVIA EN GRANDE': 'LARGE PREVIEW',
  'Así se verá este diseño dentro del juego.':
      'This is how the design will look in the game.',
  'Artículo cosmético · no da ventajas':
      'Cosmetic item · no competitive advantage',
  'TU SALDO': 'YOUR BALANCE',
  'DESPUÉS DE COMPRAR': 'AFTER PURCHASE',
  'YA ESTÁ EN USO': 'ALREADY EQUIPPED',
  'USAR ESTE DISEÑO': 'USE THIS DESIGN',
  'USAR': 'USE',
  'EN USO': 'EQUIPPED',
  'Mis diseños': 'My designs',
  'Cambiar artículos comprados': 'Change purchased items',
  'MIS DISEÑOS': 'MY DESIGNS',
  'Cambia aquí los artículos que ya compraste.':
      'Change the items you already own here.',
  'TEMAS': 'THEMES',
  'DADOS': 'DICE',
  'FICHAS': 'PIECES',
  'AVATARES': 'AVATARS',
  'Solo aparecen artículos comprados. Cada jugador conserva su propio lado.':
      'Only purchased items appear. Each player keeps their own side.',
  'EN COLECCIÓN': 'OWNED',
  'BÁSICO': 'BASIC',
  'ESPECIAL': 'SPECIAL',
  'RARO': 'RARE',
  'ÉPICO': 'EPIC',
  'LEGENDARIO': 'LEGENDARY',
  'GRATIS': 'FREE',
  'Tema completo': 'Full theme',
  'Tema premium': 'Premium theme',
  'Diseño de dados': 'Dice design',
  'Diseño de fichas': 'Piece design',
  'Diseño equipado.': 'Design equipped.',
  'Añadir monedas': 'Add coins',
  '+ MONEDAS': '+ COINS',
  'PREMIO': 'REWARD',
  'VER ANUNCIO · +100': 'WATCH AD · +100',
  'PREPARANDO ANUNCIO': 'PREPARING AD',
  'Mira un anuncio y recibe 100 monedas.': 'Watch an ad and receive 100 coins.',
  '¡Recibiste 100 monedas!': 'You received 100 coins!',
  'El anuncio no se completó.': 'The ad was not completed.',
  'SALDO PARA PROBAR': 'TEST BALANCE',
  'SALDO ACTUAL': 'CURRENT BALANCE',
  'Saldo local para probar la tienda': 'Local balance for testing the shop',
  'MODO DE PRUEBA · No se realiza ningún cobro. Las compras reales se conectarán con App Store y Google Play.':
      'TEST MODE · No charge is made. Real purchases will connect to the App Store and Google Play.',
  'AÑADIR': 'ADD',
  'Caja de prueba': 'Test coin box',
  'Paquete pequeño': 'Small pack',
  'Paquete mediano': 'Medium pack',
  'Paquete grande': 'Large pack',
  'No tienes monedas suficientes.': 'You do not have enough coins.',
  'Ese artículo ya está en tu colección.':
      'That item is already in your collection.',
  'Ese diseño ya está activo.': 'That design is already active.',
  'Los artículos de la tienda son solamente cosméticos.':
      'Shop items are cosmetic only.',
  'Espacio reservado para banner adaptable':
      'Reserved space for a responsive banner',
  'Cada jugador dispone de un solo espacio. Las trampas rivales permanecen ocultas hasta que una ficha las activa.':
      'Each player has one slot. Rival traps stay hidden until a piece triggers them.',
  'El Escudo se guarda y se activa solo. Cada trampa se arma en el cristal que la entregó, y puedes mantener varias en el tablero. Las trampas rivales permanecen ocultas hasta activarse.':
      'Shield is stored and activates on its own. Every trap arms on the crystal that awarded it, and you may keep several on the board. Rival traps stay hidden until triggered.',
  'Dados Clásicos': 'Classic Dice',
  'Diseño básico': 'Basic design',
  'Tablero Clásico': 'Classic Board',
  'Colores originales': 'Original colors',
  'Fichas Clásicas': 'Classic Pieces',
  'Estrellas originales': 'Original stars',
  'Jugador Pop': 'Pop Player',
  'Emblema clásico': 'Classic emblem',
  'Dados Galaxia': 'Galaxy Dice',
  'Nebulosa brillante': 'Bright nebula',
  'Dados Caramelo': 'Candy Dice',
  'Rosa y naranja': 'Pink and orange',
  'Dados Volcán': 'Volcano Dice',
  'Fuego y lava': 'Fire and lava',
  'Dados Hielo': 'Ice Dice',
  'Cristal congelado': 'Frozen crystal',
  'Dados Arcade': 'Arcade Dice',
  'Neón retro': 'Retro neon',
  'Fichas Robot': 'Robot Pieces',
  'Astro Pop': 'Astro Pop',
  'Avatar espacial': 'Space avatar',
  'Ninja Pixel': 'Pixel Ninja',
  'Avatar sigiloso': 'Stealth avatar',
  'Robot Turbo': 'Turbo Robot',
  'Avatar mecánico': 'Mechanical avatar',
  'Explorador Pop': 'Pop Explorer',
  'Avatar aventurero': 'Adventure avatar',
  'Ciudad Futurista': 'Future City',
  'Rascacielos, neón y energía en movimiento':
      'Skyscrapers, neon, and moving energy',
  'Templo de las Pirámides': 'Pyramid Temple',
  'Dunas doradas y monumentos bajo el sol':
      'Golden dunes and monuments beneath the sun',
  'Selva Viva': 'Living Jungle',
  'Río, hojas y luciérnagas en movimiento':
      'River, leaves, and moving fireflies',
  'Arcade Retro': 'Retro Arcade',
  'Atardecer pixelado y pista de neón en movimiento':
      'Pixel sunset and moving neon track',
  'Aurora Ártica': 'Arctic Aurora',
  'Luces polares sobre montañas de hielo': 'Northern lights over icy mountains',
  'Cosmic Realms Red': 'Cosmic Realms Red',
  'Pack con fichas, ruta, entradas y estrellas cósmicas':
      'Pack with cosmic pieces, path, entrances, and safe stars',
  'Cosmic Realms Yellow': 'Cosmic Realms Yellow',
  'Pack con fichas, ruta, entradas y estrellas cósmicas amarillas':
      'Pack with yellow cosmic pieces, path, entrances, and safe stars',
  'Cosmic Realms Blue': 'Cosmic Realms Blue',
  'Pack con fichas, ruta, entradas y estrellas cósmicas azules':
      'Pack with blue cosmic pieces, path, entrances, and safe stars',
  'Cosmic Realms Green': 'Cosmic Realms Green',
  'Pack con fichas, ruta, entradas y estrellas cósmicas verdes':
      'Pack with green cosmic pieces, path, entrances, and safe stars',
  'Dados Perla': 'Pearl Dice',
  'Brillo del océano': 'Ocean shimmer',
  'Dados Prisma': 'Prism Dice',
  'Color en cada faceta': 'Color on every facet',
  'Dados Medianoche': 'Midnight Dice',
  'Constelaciones doradas': 'Golden constellations',
  'Fichas Cristal': 'Crystal Pieces',
  'Gemas con reflejo': 'Shimmering gems',
  'Fichas Cohete': 'Rocket Pieces',
  'Despega por el tablero': 'Blast across the board',
  'Fichas Corona': 'Crown Pieces',
  'Acabado digno del podio': 'A podium-worthy finish',
  'Fichas Pulso Neón': 'Neon Pulse Pieces',
  'Combinan con Ciudad Futurista': 'Matches Future City',
  'Fichas Escarabajo Solar': 'Solar Scarab Pieces',
  'Combinan con Templo de las Pirámides': 'Matches Pyramid Temple',
  'Fichas Tótem Selvático': 'Jungle Totem Pieces',
  'Combinan con Selva Viva': 'Matches Living Jungle',
  'Fichas Pixel Blaster': 'Pixel Blaster Pieces',
  'Combinan con Arcade Retro': 'Matches Retro Arcade',
  'Fichas Fragmento Aurora': 'Aurora Shard Pieces',
  'Combinan con Aurora Ártica': 'Matches Arctic Aurora',
  'Cometa Pop': 'Pop Comet',
  'Sonrisa a toda velocidad': 'A smile at full speed',
  'Axolotl Splash': 'Axolotl Splash',
  'Mascota de agua y color': 'A colorful water mascot',
  'Tucán Turbo': 'Turbo Toucan',
  'Pico grande, juego grande': 'Big beak, big game',
  'Colección destacada': 'Featured collection',
  'Elige una colección': 'Choose a collection',

  // Settings and language.
  'Controla tu experiencia de juego': 'Control your game experience',
  'Sonido': 'Sound',
  'Dados, fichas, capturas y efectos': 'Dice, pieces, captures, and effects',
  'Música': 'Music',
  'Menú y música de partida': 'Menu and game music',
  'Vibración': 'Vibration',
  'Respuesta al lanzar y capturar': 'Feedback when rolling and capturing',
  'Guía de lanzamiento': 'Roll guide',
  'Señala los dados y las fichas disponibles':
      'Points to the dice and available pieces',
  'Mano para los dados': 'Dice hand',
  'Elige cómo aparece la guía de lanzamiento':
      'Choose how the roll guide appears',
  'IZQUIERDA': 'LEFT',
  'DERECHA': 'RIGHT',
  'Idioma': 'Language',
  'Idioma del sistema': 'System language',
  'Sistema · English': 'System · English',
  'Usar el idioma del dispositivo': 'Use the device language',
  'Mostrar el juego en español': 'Display the game in Spanish',
  'Mostrar el juego en inglés': 'Display the game in English',
  'Selecciona el idioma': 'Choose language',
  'Español': 'Español',
  'English': 'English',
  'Spanish': 'Spanish',
  'Inglés': 'English',
  'Privacidad y políticas': 'Privacy and policies',
  'Ayuda y cómo jugar': 'Help and how to play',
  'Política de privacidad': 'Privacy policy',
  'Términos de uso': 'Terms of use',
  'Política de nombres y conducta': 'Name and conduct policy',
  'Nombres y conducta': 'Names and conduct',
  'Publicidad y preferencias': 'Advertising and preferences',
  'Publicidad': 'Advertising',
  'Opciones de privacidad de anuncios': 'Ad privacy options',
  'Analítica anónima': 'Anonymous analytics',
  'Ayuda a mejorar el juego sin enviar tu nombre ni correo':
      'Helps improve the game without sending your name or email',
  'No se pudo guardar la preferencia de analítica.':
      'The analytics preference could not be saved.',
  'Eliminar cuenta y datos': 'Delete account and data',
  'Eliminar datos': 'Delete data',
  _privacyDescription:
      'The app stores the profile, coins, cosmetic purchases, and preferences locally. If you enable anonymous analytics, Google Analytics collects match, resume, tutorial, optional-ad, currency, and shop events to improve the game. We do not send the name, email, messages, flag, or avatar.',
  'Parchís Pop es un juego de entretenimiento. Las monedas de esta versión son virtuales, no tienen valor monetario y no otorgan ventajas competitivas.':
      'Parchís Pop is an entertainment game. Coins in this version are virtual, have no monetary value, and do not provide competitive advantages.',
  'Parchís Pop es un juego de entretenimiento. Las monedas de esta versión son de prueba, no tienen valor monetario y no otorgan ventajas competitivas.':
      'Parchís Pop is an entertainment game. Coins in this version are for testing, have no monetary value, and do not provide competitive advantages.',
  'No se permiten nombres ofensivos, amenazas, acoso ni contenido sexual. Los mensajes durante la partida se limitarán a frases preaprobadas.':
      'Offensive names, threats, harassment, and sexual content are not allowed. In-game messages are limited to preapproved phrases.',
  'En Android y iOS pueden aparecer banners adaptables únicamente fuera de la partida, la guía y la búsqueda de jugadores. Los anuncios recompensados solo se abren cuando eliges voluntariamente duplicar el premio al finalizar la mesa. Jugar otra vez, Volver al inicio y Reanudar nunca muestran anuncios. El premio se entrega únicamente al completar el anuncio. La aplicación solicita consentimiento cuando corresponde y ofrece opciones para administrar la privacidad publicitaria. macOS no muestra banners ni anuncios recompensados.':
      'On Android and iOS, adaptive banners may appear only outside matches, the guide, and matchmaking. Rewarded ads open only when you voluntarily choose to double the reward after the table finishes. Play Again, Back to Home, and Resume never show ads. A reward is granted only after the ad is completed. The app requests consent when required and provides options to manage ad privacy. macOS does not show banners or rewarded ads.',
  'Android y iOS pueden mostrar banners únicamente fuera de la partida, la guía y la búsqueda de jugadores. Los anuncios recompensados son voluntarios al finalizar la mesa. Jugar otra vez, Volver al inicio y Reanudar nunca abren anuncios. Puedes administrar el consentimiento y las preferencias disponibles desde esta pantalla. La versión de macOS no muestra estos anuncios.':
      'Android and iOS may show banners only outside matches, the guide, and matchmaking. Rewarded ads are optional after the table finishes. Play Again, Back to Home, and Resume never open ads. You can manage consent and available preferences from this screen. The macOS version does not show these ads.',
  'El perfil actual vive en el dispositivo. El flujo definitivo permitirá borrar tanto los datos locales como la cuenta online cuando el servicio de autenticación esté conectado.':
      'The current profile lives on this device. The final flow will let you delete both local data and the online account once the authentication service is connected.',
  'El perfil y sus credenciales se guardan localmente. Desde Mi perfil puedes usar Eliminar cuenta y datos para borrar del dispositivo el perfil, la contraseña protegida, las monedas, los cosméticos y las preferencias asociadas.':
      'The profile and credentials are stored locally. From My Profile, use Delete account and data to remove the profile, protected password, coins, cosmetics, and associated preferences from this device.',
  'Se borrarán de este dispositivo el perfil, las credenciales locales, las monedas y los cosméticos. Esta acción no se puede deshacer.':
      'The profile, local credentials, coins, and cosmetics will be deleted from this device. This action cannot be undone.',
  'Eliminar definitivamente': 'Delete permanently',
  'No se pudo abrir la política. Visita liisgo.com.':
      'The policy could not be opened. Visit liisgo.com.',

  // Guide.
  'Reglas claras, ejemplos rápidos y efectos que puedes probar.':
      'Clear rules, quick examples, and effects you can try.',
  'MODO CAOS': 'CHAOS MODE',
  'Parchís clásico': 'Classic Parcheesi',
  'De la cárcel a la victoria': 'From base to victory',
  'De la salida a la victoria': 'From the start to victory',
  'Rápido · 2 fichas': 'Fast · 2 pieces',
  '2 FICHAS': '2 PIECES',
  'Cada jugador usa 2 fichas en el tablero completo de 68 casillas.':
      'Each player uses 2 pieces on the complete 68-space board.',
  'Las dos fichas empiezan juntas en la salida; no pasan por la cárcel.':
      'Both pieces begin together on the starting space; they do not wait in base.',
  'Gana quien lleve primero sus 2 fichas al centro.':
      'The first player to bring both pieces to the center wins.',
  'Empieza de inmediato': 'Start immediately',
  'SIN 5': 'NO 5 NEEDED',
  'No necesitas sacar un 5 para comenzar: toca una ficha y elige un movimiento legal.':
      'You do not need a 5 to begin: tap a piece and choose a legal move.',
  'La pareja inicial está protegida y no bloquea el paso como barrera.':
      'The initial pair is protected and does not block the route like a blockade.',
  'Cuando solo existe una jugada legal, el juego la realiza automáticamente.':
      'When only one legal move exists, the game performs it automatically.',
  'Dados y decisiones': 'Dice and decisions',
  'Puedes repartir los dos dados entre tus fichas o usar TODOS con una sola ficha.':
      'You may split the dice between your pieces or use ALL with one piece.',
  'Un doble conserva sus 2 usos y concede otra tirada al completar los movimientos.':
      'A double keeps both uses and grants another roll after the moves are completed.',
  'Debes obtener el número exacto para entrar a la meta.':
      'You need the exact number to reach home.',
  'Capturas y regreso': 'Captures and return',
  'Captura al caer exactamente sobre una ficha rival fuera de una casilla segura.':
      'Capture by landing exactly on a rival piece outside a safe space.',
  'La ficha capturada vuelve a su salida, no a una cárcel.':
      'A captured piece returns to its starting space, not to base.',
  'Capturar concede +20 y completar una ficha concede +10.':
      'A capture grants +20, and bringing a piece home grants +10.',
  'Reglas que se conservan': 'Rules that remain',
  'Se mantienen los seguros, barreras, entradas de color y pasillos de 7 casillas.':
      'Safe spaces, blockades, colored entrances, and 7-space home lanes remain.',
  'Quick Pop acorta la partida sin recortar el recorrido original.':
      'Quick Pop shortens the match without trimming the original route.',
  'Quick Pop: tablero completo, 2 fichas ya en salida y una carrera más corta sin esperar un 5.':
      'Quick Pop: the complete board, 2 pieces already at the start, and a shorter race without waiting for a 5.',
  '2 fichas': '2 pieces',
  'Sin 5 de salida': 'No starting 5',
  'Objetivo y tablero': 'Goal and board',
  'Cada jugador controla 4 fichas y lanza 2 dados.':
      'Each player controls 4 pieces and rolls 2 dice.',
  'Gana quien coloque primero sus 4 fichas en la meta.':
      'The first player to bring all 4 pieces home wins.',
  'Recorre 64 casillas comunes desde tu salida, gira por las 7 casillas de tu pasillo y llega al centro.':
      'Travel 64 shared spaces from your start, turn through the 7 spaces of your home lane, and reach the center.',
  'Salir con un 5': 'Leave base with a 5',
  'Una ficha sale de la cárcel solo con un 5 físico en uno de los dados. No vale sumar los dos dados.':
      'A piece leaves base only with a physical 5 on either die. The dice cannot be added together.',
  'Un doble 5 puede sacar 2 fichas. Si todas están fuera —o la salida está bloqueada— el 5 mueve 5 pasos.':
      'Double 5 can release 2 pieces. If all are out—or the start is blocked—each 5 moves 5 spaces.',
  'Mientras queden fichas en la cárcel y la salida esté libre, cada 5 se usa obligatoriamente como SALIDA.':
      'While pieces remain in base and the start is open, every 5 must be used to move a piece out.',
  'Si hay una sola ficha rival en tu salida, el 5 la captura. Una barrera rival de 2 fichas impide salir.':
      'If one rival piece is on your start, a 5 captures it. A rival two-piece blockade prevents you from leaving base.',
  'Usar los dos dados': 'Use both dice',
  'Puedes repartir los valores entre fichas o usar los dos dados juntos con una misma ficha.':
      'You may split the values between pieces or use both dice together with one piece.',
  'Selecciona una ficha y elige un dado por separado o pulsa TODOS para avanzar la suma y consumir ambos dados.':
      'Choose a piece and use either die separately, or tap ALL to move the total and consume both dice.',
  'TODOS resuelve solamente la casilla final, no incluye bonos +10/+20 y desaparece después de usar uno de los dados.':
      'ALL resolves only the final space, excludes +10/+20 bonuses, and disappears after either die is used.',
  'Dobles': 'Doubles',
  'Sacar dobles concede otra tirada después de completar los movimientos legales.':
      'Rolling doubles grants another roll after all legal moves are completed.',
  'Un doble muestra un solo valor, pero conserva sus 2 usos.':
      'A double shows one value but keeps both uses.',
  'Al tercer doble consecutivo se anula esa jugada y la ficha propia más adelantada vuelve a la cárcel.':
      'On the third consecutive double, that play is canceled and your leading piece returns to base.',
  'Una ficha que ya está protegida en su pasillo final no recibe esa penalización.':
      'A piece already protected in its home lane does not receive that penalty.',
  'Seguros y salidas': 'Safe spaces and starts',
  '12 SEGUROS': '12 SAFE SPACES',
  'Las 8 estrellas y las 4 casillas de salida son seguras.':
      'The 8 stars and 4 starting spaces are safe.',
  'Dos colores contrarios no pueden compartir un seguro. Dos fichas propias sí pueden compartirlo y forman barrera.':
      'Opposing colors cannot share a safe space. Two of your own pieces may share it and form a blockade.',
  'Un rival puede pasar sobre una ficha solitaria en un seguro, pero nunca terminar allí.':
      'A rival may pass over one piece on a safe space but can never finish there.',
  'Barreras': 'Blockades',
  'Dos fichas del mismo color en una casilla forman una barrera.':
      'Two pieces of the same color on one space form a blockade.',
  'Ninguna ficha puede atravesar una barrera, ni siquiera con doble 5.':
      'No piece can cross a blockade, even with double 5.',
  'El dueño puede mover una de las dos fichas para abrir su propia barrera.':
      'The owner may move either piece to open their own blockade.',
  'Tu entrada y pasillo': 'Your entrance and home lane',
  '5 FÍSICO': 'PHYSICAL 5',
  'Todas tus fichas giran siempre por la entrada y el pasillo de su propio color.':
      'All your pieces always turn through the entrance and home lane of their own color.',
  'Una rival solitaria en la puerta bloquea el paso normal. Si estás justo antes y usas un 5 físico, la capturas, cruzas y completas los 5 pasos dentro del pasillo.':
      'One rival piece at the entrance blocks normal passage. If you are immediately before it and use a physical 5, you capture it, cross, and complete all 5 spaces inside your lane.',
  'Posiciones anteriores: rojo 63, verde 12, amarillo 29 y azul 46.':
      'Previous spaces: red 63, green 12, yellow 29, and blue 46.',
  'Dos rivales en la puerta forman una barrera imposible de romper.':
      'Two rivals at the entrance form an unbreakable blockade.',
  'Capturas y bono +20': 'Captures and +20 bonus',
  'Para capturar debes caer exactamente sobre una ficha rival en una casilla blanca.':
      'To capture, land exactly on a rival piece on a white space.',
  'La ficha capturada vuelve a su cárcel y recibes un movimiento de 20 pasos.':
      'The captured piece returns to base and you receive a 20-space move.',
  'El bono +20 se usa completo con una sola ficha; no se divide.':
      'The +20 bonus must be used by one piece and cannot be split.',
  'Meta, +10 y victoria': 'Home, +10, and victory',
  'Debes obtener el número exacto para entrar a la meta; no hay rebote ni exceso.':
      'You need the exact number to reach home; there is no bounce or overshoot.',
  'Completar una ficha concede un movimiento adicional de 10 pasos con otra ficha legal.':
      'Finishing a piece grants an extra 10-space move with another legal piece.',
  'Al completar la cuarta ficha termina la partida y aparece la celebración de victoria.':
      'Finishing the fourth piece ends the game and starts the victory celebration.',
  'Cristales sorpresa': 'Surprise crystals',
  'Caos conserva todas las reglas tradicionales y añade cristales, poderes y trampas.':
      'Chaos keeps all traditional rules and adds crystals, powers, and traps.',
  'Modo Caos: todas las reglas tradicionales + cristales, poderes automáticos y varias trampas ocultas.':
      'Chaos mode: all traditional rules + crystals, automatic powers, and several hidden traps.',
  'Hay siempre 1 cristal activo en cada lado del tablero. Debes caer exactamente sobre él para recogerlo.':
      'There is always 1 active crystal on each side. Land exactly on it to collect it.',
  'Al recogerlo desaparece y reaparece de inmediato en otra casilla válida del mismo lado.':
      'After collection it disappears and immediately respawns on another valid space on the same side.',
  'Un solo espacio': 'One slot',
  'Poderes automáticos': 'Automatic powers',
  'El Escudo se guarda para el jugador completo y se activa automáticamente cuando cualquiera de sus cuatro fichas cae en una trampa rival.':
      'Shield belongs to the whole player and activates automatically when any of their four pieces lands on a rival trap.',
  'El Escudo y la trampa se consumen al bloquear el efecto. Turbo se guarda y el jugador decide cuándo usarlo.':
      'Shield and the trap are consumed when the effect is blocked. Turbo is stored until the player chooses to use it.',
  'Tener un Escudo o Turbo guardado nunca impide recoger y armar nuevas trampas.':
      'A stored Shield or Turbo never prevents collecting and arming new traps.',
  'Cada jugador tiene un único espacio combinado: un poder guardado o una trampa activa.':
      'Each player has one combined slot: one stored power or one active trap.',
  'El Escudo se guarda y se activa automáticamente al caer en una trampa rival. Turbo se activa cuando el jugador decide usarlo.':
      'Shield is stored and activates automatically on a rival trap. Turbo activates when the player chooses to use it.',
  'El espacio vuelve a quedar libre cuando el poder se usa o un rival activa la trampa.':
      'The slot becomes free when the power is used or a rival triggers the trap.',
  'Trampas ocultas': 'Hidden traps',
  'Pegamento, Retroceso, Cárcel y Bomba se arman automáticamente en la misma casilla donde recogiste el cristal.':
      'Glue, Setback, Prison, and Bomb arm automatically on the same space where you collected the crystal.',
  'Puedes mantener varias trampas en el tablero. Solo el dueño ve sus tipos y ubicaciones; los rivales ven únicamente cuántas trampas ocultas existen.':
      'You may keep several traps on the board. Only the owner sees their types and locations; rivals only see how many hidden traps exist.',
  'Cada trampa es de un solo uso, no afecta a su dueño y un Escudo puede bloquearla.':
      'Each trap is single-use, never affects its owner, and can be blocked by a Shield.',
  'Las trampas son ocultas, de un solo uso y ocupan el único espacio del jugador. No se colocan en seguros, salidas ni pasillos.':
      'Traps are hidden, single-use, and occupy the player’s only slot. They cannot be placed on safe spaces, starts, or home lanes.',
  'Las trampas son ocultas, de un solo uso y se arman automáticamente en el cristal. Puedes tener varias; no aparecen en seguros, salidas ni pasillos.':
      'Traps are hidden, single-use, and arm automatically on the crystal. You may have several; they do not appear on safe spaces, starts, or home lanes.',
  'Solo el dueño ve el tipo y la ubicación de su trampa. Los rivales ven “Trampa oculta activa”.':
      'Only the owner sees a trap’s type and location. Rivals see “Hidden trap active.”',
  'Son de un solo uso, no afectan a su dueño y un Escudo puede bloquearlas.':
      'They are single-use, never affect their owner, and can be blocked by a Shield.',
  'Nunca aparecen en seguros, salidas, pasillos de meta, otro cristal ni otra trampa.':
      'They never appear on safe spaces, starts, home lanes, another crystal, or another trap.',
  'Laboratorio de poderes': 'Power lab',
  'Laboratorio de trampas': 'Trap lab',
  'TRAMPAS Y ANIMACIONES': 'TRAPS AND ANIMATIONS',
  'Elige un efecto para verlo en acción': 'Choose an effect to see it',
  'Toca cada trampa o reproduce todas sus animaciones.':
      'Tap each trap or play all their animations.',
  'Míralos en acción': 'See them in action',
  'Ver todos': 'Play all',
  'Detener': 'Stop',
  'Ver trampas': 'View traps',
  'Probar efectos': 'Try effects',
  'Ver detalle': 'View details',
  'CHULETA RÁPIDA': 'QUICK REFERENCE',
  '5 = SALIDA': '5 = START',
  'Captura = +20': 'Capture = +20',
  'Meta = +10': 'Home = +10',
  'Doble = otra tirada': 'Double = roll again',
  '3 dobles = penalización': '3 doubles = penalty',
  'Meta = número exacto': 'Home = exact number',
  'Modo Tradicional: carrera pura con dados, seguros, barreras, capturas y estrategia.':
      'Traditional mode: pure dice racing with safe spaces, blockades, captures, and strategy.',
  'Modo Caos: todas las reglas tradicionales + cristales, un espacio de poder y trampas ocultas.':
      'Chaos mode: all traditional rules plus crystals, one power slot, and hidden traps.',
  'Toca una tarjeta o usa “Ver todos” para mirar la secuencia completa.':
      'Tap a card or use “Play all” to watch the full sequence.',
  '¡TURBO!': 'TURBO!',
  'TURNO PERDIDO': 'TURN LOST',
  '¡BUM! A LA CÁRCEL': 'BOOM! BACK TO BASE',
};

class PopText extends StatelessWidget {
  const PopText(
    this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  });

  final String data;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final Color? selectionColor;

  @override
  Widget build(BuildContext context) => material.Text(
    appTranslate(context, data),
    style: style,
    strutStyle: strutStyle,
    textAlign: textAlign,
    textDirection: textDirection,
    locale: locale,
    softWrap: softWrap,
    overflow: overflow,
    textScaler: textScaler,
    maxLines: maxLines,
    semanticsLabel: semanticsLabel == null
        ? null
        : appTranslate(context, semanticsLabel!),
    textWidthBasis: textWidthBasis,
    textHeightBehavior: textHeightBehavior,
    selectionColor: selectionColor,
  );
}
