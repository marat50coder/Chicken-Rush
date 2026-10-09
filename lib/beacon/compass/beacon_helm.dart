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

    // Early-boot URL from a PUSH NOTIFICATION tap wins immediately.
    // We must NOT treat OneLink / AppsFlyer URLs the same way — those
    // need to go through the attribution + DecreeFetch flow, otherwise
    // the WebView opens the raw onelink.me redirect page (NO sub_ids,
    // partner site shows every parameter red). SkyLadder makes the
    // same distinction. Reject anything that looks like a OneLink or
    // the AF SDK's own tracking domain here; MeshTelemetry's UDL
    // callback (`onDeepLinking`) will consume the deep-link data.
    final early = MooringNote.instance.takeUrl();
    final earlyIsOnelink = early != null &&
        (early.contains('onelink.me') ||
            early.contains('appsflyer.com') ||
            early.contains('.app.goo.gl'));
    if (early != null && early.startsWith('http') && !earlyIsOnelink) {
      diag('BeaconHelm',
          'decide() → WebHarbor via mooringNote (push URL) url=$early');
      await AnchorVault.instance.rememberDecree(openWeb: true, url: early);
      return WebHarbor(
        url: early,
        mark: TrailMark.pushRelaunch,
      );
    }
    if (earlyIsOnelink) {
      diag('BeaconHelm',
          'mooringNote carried OneLink url=$early — IGNORED, routing through attribution');
    }

    // Reach probe. If offline → Becalmed (don't try to fetch).
    final reachable = await TideScout.instance.isReachable();
    diag('BeaconHelm', 'reach probe reachable=$reachable');
    if (!reachable) {
      return const BecalmedHarbor(mark: TrailMark.reachLost);
    }

    final isFirst = await AnchorVault.instance.isFirstBoot();
    diag('BeaconHelm', 'isFirstBoot=$isFirst');

    // NOTE: we intentionally do NOT short-circuit returning users with
    // the cached decree. On a returning launch the user may have just
    // clicked a NEW OneLink (new campaign, new sub_ids, new
    // deep_link_value) — serving the previous session's cached URL
    // would make the partner site see stale sub_ids (every param red)
    // and testing new OneLinks would be impossible. We always run
    // attribution → DecreeFetch when the network is live; the cache
    // is only used as a fallback inside the catch below when the POST
    // fails. SkyLadder uses an 8-day cache window + token-refresh
    // reissue; we favor the simpler always-fetch pattern which costs
    // ~1 second per launch but guarantees fresh params every click.

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

    // Decree failed (timeout, network, 5xx)? Fall back to the cached
    // decree from a previous session — better to show the known-good
    // URL than block the user.
    if (decree == null || !decree.valid) {
      final cached = await AnchorVault.instance.recallDecree();
      if (cached.openWeb == true && cached.url != null) {
        diag('BeaconHelm',
            'FINAL → WebHarbor via CACHE fallback url=${cached.url}');
        unawaited(ChimeBridge.instance.boot());
        return WebHarbor(url: cached.url!, mark: TrailMark.cachedWebReturn);
      }
      diag('BeaconHelm', 'FINAL → GameHarbor (no valid decree, no cache)');
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
