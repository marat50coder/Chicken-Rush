// ===================================================================
// BeaconHelm — orchestrates the gray-flow decision.
//
// Single entry point: `decide()`. Guaranteed to return within the hold
// configured in FabricPlan — if backend / credentials are missing we
// return GameHarbor so the user always sees the white game within a
// predictable time.
// ===================================================================

import 'dart:async';

import '../plan/fabric_plan.dart';
import '../current/anchor_vault.dart';
import '../current/chime_bridge.dart';
import '../current/decree_fetch.dart';
import '../current/mesh_telemetry.dart';
import '../current/mooring_note.dart';
import '../current/tide_scout.dart';
import 'harbor.dart';

class BeaconHelm {
  BeaconHelm._();
  static final BeaconHelm instance = BeaconHelm._();

  /// Compute what the UI should show next.
  Future<Harbor> decide() async {
    // Dormant gate → always game. No network calls, no attribution SDK,
    // no notification channels created. White build.
    if (!fabricCredentialsLive) {
      return const GameHarbor(mark: TrailMark.firstBoot);
    }

    // Early-boot URL (push cold-boot or deep link) wins immediately.
    final early = MooringNote.instance.takeUrl();
    if (early != null && early.startsWith('http')) {
      await AnchorVault.instance.rememberDecree(openWeb: true, url: early);
      return WebHarbor(
        url: early,
        mark: TrailMark.pushRelaunch,
      );
    }

    // Reach probe. If offline → Becalmed (don't try to fetch).
    final reachable = await TideScout.instance.isReachable();
    if (!reachable) {
      return const BecalmedHarbor(mark: TrailMark.reachLost);
    }

    final isFirst = await AnchorVault.instance.isFirstBoot();

    // Returning user with a cached web decision → fast re-use.
    if (!isFirst) {
      final cached = await AnchorVault.instance.recallDecree();
      if (cached.openWeb == true && cached.url != null) {
        return WebHarbor(
          url: cached.url!,
          mark: TrailMark.cachedWebReturn,
        );
      }
      if (cached.openWeb == false) {
        return const GameHarbor(mark: TrailMark.cachedGameReturn);
      }
    }

    // Fresh decision path.
    final breadcrumbs = await MeshTelemetry.instance.awaitBreadcrumbs();
    final hold = isFirst
        ? FabricPlan.firstInstallHold
        : FabricPlan.returningHold;

    Decree? decree;
    try {
      decree = await DecreeFetch.instance
          .ask(isFirstLaunch: isFirst, breadcrumbs: breadcrumbs)
          .timeout(hold);
    } on TimeoutException {
      decree = null;
    } catch (_) {
      decree = null;
    }

    await AnchorVault.instance.markBooted();

    if (decree == null || !decree.valid) {
      return const GameHarbor(mark: TrailMark.firstBoot);
    }
    if (!decree.openWeb) {
      return const GameHarbor(mark: TrailMark.firstBoot);
    }

    // Prime chime channel exactly once (after we know we are showing web).
    unawaited(ChimeBridge.instance.boot());
    return WebHarbor(
      url: decree.url!,
      mark: TrailMark.firstBoot,
    );
  }
}
