import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:package_info_plus/package_info_plus.dart';

const _androidBannerTestId = 'ca-app-pub-3940256099942544/9214589741';
const _iosBannerTestId = 'ca-app-pub-3940256099942544/2435281174';
const _androidRewardedTestId = 'ca-app-pub-3940256099942544/5224354917';
const _iosRewardedTestId = 'ca-app-pub-3940256099942544/1712485313';

const _androidBannerReleaseId = 'ca-app-pub-8588489900323524/5419059196';
const _iosBannerReleaseId = 'ca-app-pub-8588489900323524/2792895853';
const _androidRewardedReleaseId = 'ca-app-pub-8588489900323524/9654506032';
const _iosRewardedReleaseId = 'ca-app-pub-8588489900323524/2250538595';

// Keeps store screenshots free of test-ad UI when running a dedicated capture
// build. It is false in every normal debug and release build.
const _disableAdsForStoreCapture = bool.fromEnvironment('STORE_SCREENSHOTS');

/// Allows an optimized QA build to use Google's official test ad units.
///
/// Debug builds always use test units. Release builds use the production units
/// unless they are compiled with `--dart-define=QA_TEST_ADS=true`.
const qaTestAdsEnabled = bool.fromEnvironment('QA_TEST_ADS');

bool shouldUseTestAdUnits({
  required bool debugBuild,
  required bool qaOverride,
}) => debugBuild || qaOverride;

bool supportsMobileAds(TargetPlatform platform, {bool isWeb = false}) =>
    !isWeb &&
    (platform == TargetPlatform.android || platform == TargetPlatform.iOS);

RequestConfiguration familySafeAdRequestConfiguration() =>
    RequestConfiguration(maxAdContentRating: MaxAdContentRating.g);

/// Terminal outcome of an explicit rewarded-ad request.
///
/// [dismissed] means an ad was shown but closed before a reward was earned.
/// [unavailable] means no ad could be presented, while [failed] means AdMob
/// attempted to present one and reported an error.
enum RewardedAdResult {
  earned,
  dismissed,
  unavailable,
  failed;

  bool get didEarnReward => this == RewardedAdResult.earned;
}

abstract class AppAdsController extends ChangeNotifier {
  final Set<Object> _bannerSuppressors = <Object>{};
  bool _baseDisposed = false;

  bool get supported;
  bool get adsReady;
  bool get rewardedReady;
  bool get privacyOptionsRequired;

  /// Whether the persistent banner may currently use screen space.
  ///
  /// The normal Android/iOS experience keeps the banner in its reserved bottom
  /// strip across navigation. A temporary suppressor remains available only
  /// for exceptional overlays that explicitly cannot share that space.
  bool get bannerAllowed => _bannerSuppressors.isEmpty;

  Object suppressBanner() {
    final token = Object();
    _bannerSuppressors.add(token);
    _notifyBannerVisibilityChanged();
    return token;
  }

  void restoreBanner(Object token) {
    if (_bannerSuppressors.remove(token)) {
      _notifyBannerVisibilityChanged();
    }
  }

  void _notifyBannerVisibilityChanged() {
    scheduleMicrotask(() {
      if (!_baseDisposed) notifyListeners();
    });
  }

  Future<void> initialize();

  /// Starts or refreshes the rewarded-ad preload without blocking the caller.
  /// Implementations must keep this operation idempotent.
  void preloadRewarded() {}

  /// Presents a rewarded ad and preserves its exact terminal outcome.
  Future<RewardedAdResult> showRewardedWithResult();

  /// Compatibility wrapper for callers that only need to know whether the
  /// reward was earned.
  Future<bool> showRewarded() async =>
      (await showRewardedWithResult()).didEarnReward;

  Future<void> showPrivacyOptions();
  Widget buildBanner(BuildContext context);

  @mustCallSuper
  @override
  void dispose() {
    _baseDisposed = true;
    _bannerSuppressors.clear();
    super.dispose();
  }
}

AppAdsController createAppAdsController() {
  if (_disableAdsForStoreCapture ||
      !supportsMobileAds(defaultTargetPlatform, isWeb: kIsWeb)) {
    return NoopAppAdsController();
  }
  return GoogleMobileAdsController(platform: defaultTargetPlatform);
}

class NoopAppAdsController extends AppAdsController {
  @override
  bool get supported => false;

  @override
  bool get adsReady => false;

  @override
  bool get rewardedReady => false;

  @override
  bool get privacyOptionsRequired => false;

  @override
  Future<void> initialize() async {}

  @override
  Future<RewardedAdResult> showRewardedWithResult() async =>
      RewardedAdResult.unavailable;

  @override
  Future<void> showPrivacyOptions() async {}

  @override
  Widget buildBanner(BuildContext context) => const SizedBox.shrink();
}

class GoogleMobileAdsController extends AppAdsController {
  GoogleMobileAdsController({required this.platform})
    : assert(supportsMobileAds(platform));

  final TargetPlatform platform;
  RewardedAd? _rewardedAd;
  Timer? _rewardRetryTimer;
  DateTime? _rewardLoadedAt;
  int _rewardLoadFailureCount = 0;
  bool _initializing = false;
  bool _initialized = false;
  bool _adsStarting = false;
  bool _adsReady = false;
  bool _rewardLoading = false;
  bool _rewardShowing = false;
  bool _privacyOptionsRequired = false;
  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  String get _bannerAdUnitId {
    final useTestUnits = shouldUseTestAdUnits(
      debugBuild: kDebugMode,
      qaOverride: qaTestAdsEnabled,
    );
    if (platform == TargetPlatform.android) {
      return useTestUnits ? _androidBannerTestId : _androidBannerReleaseId;
    }
    return useTestUnits ? _iosBannerTestId : _iosBannerReleaseId;
  }

  String get _rewardedAdUnitId {
    final useTestUnits = shouldUseTestAdUnits(
      debugBuild: kDebugMode,
      qaOverride: qaTestAdsEnabled,
    );
    if (platform == TargetPlatform.android) {
      return useTestUnits ? _androidRewardedTestId : _androidRewardedReleaseId;
    }
    return useTestUnits ? _iosRewardedTestId : _iosRewardedReleaseId;
  }

  @override
  bool get supported => true;

  @override
  bool get adsReady => _adsReady;

  @override
  bool get rewardedReady => _rewardedAd != null && !_rewardShowing;

  @override
  bool get privacyOptionsRequired => _privacyOptionsRequired;

  @override
  Future<void> initialize() async {
    if (_initializing || _initialized) return;
    _initializing = true;
    final completed = Completer<void>();

    Future<void> finishConsentFlow() async {
      try {
        await _refreshPrivacyOptionsRequirement();
        await _startAdsIfAllowed();
      } catch (error, stackTrace) {
        debugPrint('AdMob initialization error: $error');
        debugPrintStack(stackTrace: stackTrace);
      } finally {
        if (!completed.isCompleted) completed.complete();
      }
    }

    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () {
        ConsentForm.loadAndShowConsentFormIfRequired((formError) {
          if (formError != null) {
            debugPrint(
              'AdMob consent form error '
              '${formError.errorCode}: ${formError.message}',
            );
          }
          unawaited(finishConsentFlow());
        });
      },
      (formError) {
        debugPrint(
          'AdMob consent update error '
          '${formError.errorCode}: ${formError.message}',
        );
        unawaited(finishConsentFlow());
      },
    );

    try {
      await completed.future;
    } finally {
      _initializing = false;
      _initialized = true;
    }
  }

  Future<void> _refreshPrivacyOptionsRequirement() async {
    final status = await ConsentInformation.instance
        .getPrivacyOptionsRequirementStatus();
    final required = status == PrivacyOptionsRequirementStatus.required;
    if (_privacyOptionsRequired == required) return;
    _privacyOptionsRequired = required;
    _notify();
  }

  Future<void> _startAdsIfAllowed() async {
    if (_disposed || _adsReady || _adsStarting) return;
    _adsStarting = true;
    try {
      final canRequestAds = await ConsentInformation.instance.canRequestAds();
      if (!canRequestAds) return;
      await MobileAds.instance.updateRequestConfiguration(
        familySafeAdRequestConfiguration(),
      );
      await MobileAds.instance.initialize();
      if (_disposed) return;
      _adsReady = true;
      _notify();
      _loadRewarded();
    } finally {
      _adsStarting = false;
    }
  }

  void _loadRewarded() {
    if (_disposed ||
        !_adsReady ||
        _rewardLoading ||
        _rewardShowing ||
        _rewardedAd != null) {
      return;
    }
    _rewardRetryTimer?.cancel();
    _rewardLoading = true;
    _notify();
    RewardedAd.load(
      adUnitId: _rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          if (_disposed) {
            ad.dispose();
            return;
          }
          _rewardLoading = false;
          _rewardLoadFailureCount = 0;
          _rewardLoadedAt = DateTime.now();
          _rewardedAd = ad;
          _notify();
        },
        onAdFailedToLoad: (error) {
          if (_disposed) return;
          _rewardLoading = false;
          _rewardLoadFailureCount += 1;
          debugPrint('AdMob rewarded load error: $error');
          _notify();
          final retrySeconds = switch (_rewardLoadFailureCount) {
            1 => 3,
            2 => 6,
            3 => 12,
            _ => 30,
          };
          _rewardRetryTimer = Timer(
            Duration(seconds: retrySeconds),
            preloadRewarded,
          );
        },
      ),
    );
  }

  @override
  void preloadRewarded() {
    if (_disposed) return;
    if (!_initialized) {
      if (!_initializing) unawaited(initialize());
      return;
    }
    if (!_adsReady) {
      unawaited(_startAdsIfAllowed());
      return;
    }

    // Google mobile ads should not be kept for longer than about one hour.
    // Refresh a cached ad early whenever the app resumes after a long pause.
    final loadedAt = _rewardLoadedAt;
    if (_rewardedAd != null &&
        loadedAt != null &&
        DateTime.now().difference(loadedAt) >= const Duration(minutes: 50) &&
        !_rewardShowing) {
      _rewardedAd?.dispose();
      _rewardedAd = null;
      _rewardLoadedAt = null;
      _notify();
    }
    _loadRewarded();
  }

  /// The reward is preloaded at launch. If the player reaches a reward action
  /// before AdMob has finished, give the request a short chance to complete
  /// instead of skipping straight past the ad.
  Future<RewardedAd?> _waitForRewardedAd() async {
    const deadline = Duration(seconds: 5);
    const pollInterval = Duration(milliseconds: 200);
    var waited = Duration.zero;

    while (!_disposed && _rewardedAd == null && waited < deadline) {
      await Future<void>.delayed(pollInterval);
      waited += pollInterval;
    }
    return _rewardedAd;
  }

  @override
  Future<RewardedAdResult> showRewardedWithResult() async {
    if (_rewardShowing || _disposed) return RewardedAdResult.unavailable;

    preloadRewarded();
    var ad = _rewardedAd;
    ad ??= await _waitForRewardedAd();
    if (ad == null || _rewardShowing || _disposed) {
      return RewardedAdResult.unavailable;
    }

    final completed = Completer<RewardedAdResult>();
    var earnedReward = false;
    _rewardedAd = null;
    _rewardLoadedAt = null;
    _rewardShowing = true;
    _notify();

    void finish(RewardedAdResult result) {
      if (completed.isCompleted) return;
      completed.complete(result);
      if (_disposed) return;
      _rewardShowing = false;
      _notify();
      preloadRewarded();
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (closedAd) {
        closedAd.dispose();
        finish(
          earnedReward ? RewardedAdResult.earned : RewardedAdResult.dismissed,
        );
      },
      onAdFailedToShowFullScreenContent: (failedAd, error) {
        debugPrint('AdMob rewarded show error: $error');
        failedAd.dispose();
        finish(RewardedAdResult.failed);
      },
    );
    try {
      ad.show(
        onUserEarnedReward: (_, _) {
          earnedReward = true;
        },
      );
    } catch (error) {
      debugPrint('AdMob rewarded synchronous show error: $error');
      ad.dispose();
      finish(RewardedAdResult.failed);
    }
    return completed.future;
  }

  @override
  Future<void> showPrivacyOptions() async {
    final completed = Completer<void>();
    ConsentForm.showPrivacyOptionsForm((formError) {
      if (formError != null) {
        debugPrint(
          'AdMob privacy options error '
          '${formError.errorCode}: ${formError.message}',
        );
      }
      unawaited(
        _refreshPrivacyOptionsRequirement().then((_) => _startAdsIfAllowed()),
      );
      if (!completed.isCompleted) completed.complete();
    });
    return completed.future;
  }

  @override
  Widget buildBanner(BuildContext context) => AdaptiveMobileBanner(
    key: const ValueKey('mobile-ad-banner'),
    adUnitId: _bannerAdUnitId,
  );

  @override
  void dispose() {
    _disposed = true;
    _rewardRetryTimer?.cancel();
    _rewardedAd?.dispose();
    super.dispose();
  }
}

class MobileAdsScope extends InheritedNotifier<AppAdsController> {
  const MobileAdsScope({
    super.key,
    required AppAdsController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppAdsController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<MobileAdsScope>();
    assert(scope != null, 'MobileAdsScope is missing above this context.');
    return scope!.notifier!;
  }

  static AppAdsController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MobileAdsScope>()?.notifier;
}

/// Temporarily prevents the persistent banner from taking layout space while
/// [child] is mounted. Normal screens should keep the global bottom banner.
class SuppressMobileAdBanner extends StatefulWidget {
  const SuppressMobileAdBanner({super.key, required this.child});

  final Widget child;

  @override
  State<SuppressMobileAdBanner> createState() => _SuppressMobileAdBannerState();
}

class _SuppressMobileAdBannerState extends State<SuppressMobileAdBanner> {
  AppAdsController? _controller;
  Object? _suppressionToken;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextController = MobileAdsScope.maybeOf(context);
    if (identical(nextController, _controller)) return;
    _releaseSuppression();
    _controller = nextController;
    _suppressionToken = nextController?.suppressBanner();
  }

  void _releaseSuppression() {
    final controller = _controller;
    final token = _suppressionToken;
    _controller = null;
    _suppressionToken = null;
    if (controller != null && token != null) controller.restoreBanner(token);
  }

  @override
  void dispose() {
    _releaseSuppression();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class MobileAdShell extends StatelessWidget {
  const MobileAdShell({
    super.key,
    required this.controller,
    required this.child,
  });

  final AppAdsController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!controller.supported) return child;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
        if (!controller.adsReady || keyboardOpen || !controller.bannerAllowed) {
          return child;
        }
        return Column(
          children: [
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeBottom: true,
                child: child,
              ),
            ),
            const _BuildVersionAboveBanner(),
            SafeArea(
              top: false,
              minimum: const EdgeInsets.only(top: 2),
              child: controller.buildBanner(context),
            ),
          ],
        );
      },
    );
  }
}

/// A stable place for the installed build number: immediately above the mobile
/// banner, independent of the game HUD or the active screen.
class _BuildVersionAboveBanner extends StatefulWidget {
  const _BuildVersionAboveBanner();

  @override
  State<_BuildVersionAboveBanner> createState() =>
      _BuildVersionAboveBannerState();
}

class _BuildVersionAboveBannerState extends State<_BuildVersionAboveBanner> {
  String _label = 'v…';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final package = await PackageInfo.fromPlatform();
      final build = package.buildNumber.trim();
      final label = build.isEmpty
          ? 'v${package.version}'
          : 'v${package.version}+$build';
      if (mounted) setState(() => _label = label);
    } catch (_) {
      if (mounted) setState(() => _label = 'v—');
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('version-above-ad-banner'),
    height: 19,
    width: double.infinity,
    alignment: Alignment.center,
    color: const Color(0xFFF4F7FC),
    child: Text(
      _label,
      style: const TextStyle(
        color: Color(0xFF52617D),
        fontSize: 9,
        fontWeight: FontWeight.w900,
        letterSpacing: .25,
      ),
    ),
  );
}

class AdaptiveMobileBanner extends StatefulWidget {
  const AdaptiveMobileBanner({
    super.key,
    required this.adUnitId,
    this.sizeLoader,
    this.contentBuilder,
  });

  final String adUnitId;

  /// Test/preview seam. Production uses AdMob's anchored-adaptive size API.
  @visibleForTesting
  final AdaptiveBannerSizeLoader? sizeLoader;

  /// Test/preview seam that avoids mounting a native platform ad view.
  @visibleForTesting
  final AdaptiveBannerContentBuilder? contentBuilder;

  @override
  State<AdaptiveMobileBanner> createState() => _AdaptiveMobileBannerState();
}

class _AdaptiveMobileBannerState extends State<AdaptiveMobileBanner> {
  BannerAd? _banner;
  Timer? _retryTimer;
  AdSize? _size;
  int? _requestedWidth;
  Orientation? _requestedOrientation;
  bool _loadScheduled = false;

  @override
  void didUpdateWidget(covariant AdaptiveMobileBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.adUnitId == widget.adUnitId &&
        identical(oldWidget.sizeLoader, widget.sizeLoader) &&
        identical(oldWidget.contentBuilder, widget.contentBuilder)) {
      return;
    }
    _disposeBanner();
    _requestedWidth = null;
    _requestedOrientation = null;
  }

  void _scheduleLoad(int width, Orientation orientation) {
    if (width <= 0 ||
        (_requestedWidth == width && _requestedOrientation == orientation) ||
        _loadScheduled) {
      return;
    }
    _loadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadScheduled = false;
      if (mounted) unawaited(_load(width, orientation));
    });
  }

  Future<void> _load(int width, Orientation orientation) async {
    _requestedWidth = width;
    _requestedOrientation = orientation;
    _retryTimer?.cancel();
    _disposeBanner();
    final size = await resolveAnchoredAdaptiveBannerSize(
      width,
      orientation: orientation,
      loadAdaptive: widget.sizeLoader,
    );
    if (!mounted ||
        _requestedWidth != width ||
        _requestedOrientation != orientation) {
      return;
    }
    if (size == null) {
      _scheduleRetry(width, orientation);
      return;
    }

    final contentBuilder = widget.contentBuilder;
    if (contentBuilder != null) {
      setState(() => _size = size);
      return;
    }

    final banner = BannerAd(
      adUnitId: widget.adUnitId,
      request: const AdRequest(),
      size: size,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted || ad != _banner) {
            ad.dispose();
            return;
          }
          setState(() => _size = size);
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('AdMob banner load error: $error');
          ad.dispose();
          if (!mounted || ad != _banner) return;
          setState(() {
            _banner = null;
            _size = null;
            _requestedWidth = width;
            _requestedOrientation = orientation;
          });
          _scheduleRetry(width, orientation);
        },
      ),
    );
    _banner = banner;
    await banner.load();
  }

  void _scheduleRetry(int width, Orientation orientation) {
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 30), () {
      if (!mounted ||
          _requestedWidth != width ||
          _requestedOrientation != orientation) {
        return;
      }
      setState(() {
        _requestedWidth = null;
        _requestedOrientation = null;
      });
    });
  }

  void _disposeBanner() {
    _banner?.dispose();
    _banner = null;
    _size = null;
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _disposeBanner();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.floor();
        final orientation = MediaQuery.orientationOf(context);
        _scheduleLoad(width, orientation);
        final size = _size;
        final banner = _banner;
        final height = size?.height.toDouble() ?? 50;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          key: const ValueKey('mobile-ad-banner-slot'),
          width: double.infinity,
          height: height,
          alignment: Alignment.center,
          color: const Color(0xFFF4F7FC),
          child: size != null && widget.contentBuilder != null
              ? SizedBox(
                  width: size.width.toDouble(),
                  height: size.height.toDouble(),
                  child: widget.contentBuilder!(context, size),
                )
              : size != null && banner != null
              ? SizedBox(
                  width: size.width.toDouble(),
                  height: size.height.toDouble(),
                  child: AdWidget(ad: banner),
                )
              : Semantics(
                  label: 'Publicidad',
                  child: Center(
                    child: Text(
                      'PUBLICIDAD',
                      style: TextStyle(
                        color: Color(0xFF667085),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }
}

typedef AdaptiveBannerSizeLoader = Future<AdSize?> Function(int width);

typedef AdaptiveBannerContentBuilder =
    Widget Function(BuildContext context, AdSize size);

/// Resolves a full-width anchored banner while keeping every fallback inside
/// the available logical width. Use the standard anchored-adaptive format:
/// its height stays compact on tablets, preserving the game's bottom actions.
@visibleForTesting
Future<AdSize?> resolveAnchoredAdaptiveBannerSize(
  int availableWidth, {
  Orientation orientation = Orientation.portrait,
  AdaptiveBannerSizeLoader? loadAdaptive,
}) async {
  if (availableWidth <= 0) return null;

  try {
    // The SDK's replacement only requests a *large* anchored size. This
    // compact variant is intentional so the banner never covers game actions.
    final adaptive = await (loadAdaptive == null
        // ignore: deprecated_member_use
        ? AdSize.getAnchoredAdaptiveBannerAdSize(orientation, availableWidth)
        : loadAdaptive(availableWidth));
    if (adaptive != null &&
        adaptive.width > 0 &&
        adaptive.width <= availableWidth &&
        adaptive.height > 0) {
      return adaptive;
    }
  } catch (error) {
    debugPrint('AdMob adaptive banner size error: $error');
  }

  return widthSafeBannerFallback(availableWidth);
}

@visibleForTesting
AdSize? widthSafeBannerFallback(int availableWidth) {
  if (availableWidth >= AdSize.fullBanner.width) {
    return AdSize.fullBanner;
  }
  if (availableWidth >= AdSize.banner.width) return AdSize.banner;
  return null;
}
