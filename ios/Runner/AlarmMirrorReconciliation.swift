@_weakLinked import AlarmKit
import Foundation

extension AlarmKitBridge {
  @available(iOS 26.0, *)
  func restoreRequiredNativeConfigurations(
    in snapshot: MirrorSnapshot,
    restrictedTo platformAlarmIds: Set<String>? = nil
  ) async throws -> (snapshot: MirrorSnapshot, didRestore: Bool) {
    let recordsToRestore = snapshot.pendingNormalized.filter {
      $0.value.requiresNativeRestoration == true
        && (platformAlarmIds == nil || platformAlarmIds?.contains($0.key) == true)
    }
    guard !recordsToRestore.isEmpty else {
      return (snapshot, false)
    }

    var mirror = snapshot.normalized
    var pendingMirror = snapshot.pendingNormalized
    var didRestore = false

    for (platformAlarmId, record) in recordsToRestore {
      guard let alarmId = UUID(uuidString: platformAlarmId),
        let recoveryRequest = record.scheduleRequest()
      else { throw MirrorValidationError.invalid }
      let restoredPlatformAlarmId = try await nativeClientForAlarmKit().schedule(
        id: alarmId,
        request: recoveryRequest
      )
      guard try canonicalPlatformAlarmId(restoredPlatformAlarmId) == platformAlarmId else {
        throw MirrorValidationError.invalid
      }
      pendingMirror.removeValue(forKey: platformAlarmId)
      mirror[platformAlarmId] = record.markingNativeRestored()
      try saveMirrorState(mirror, pending: pendingMirror)
      didRestore = true
    }

    return (try loadMirrorSnapshot(), didRestore)
  }

  @available(iOS 26.0, *)
  func observeAlarmUpdates() async {
    await reconcileMirrorOnObservationStart()
    for await alarms in AlarmManager.shared.alarmUpdates {
      await reconcileMirror(with: alarms)
    }
  }

  // Internal for RunnerTests to exercise the exact production launch path.
  @available(iOS 26.0, *)
  func reconcileMirrorOnObservationStart() async {
    // Launch is only a wake hint. The authoritative inventory read must happen
    // after admission to the shared mirror transaction or a concurrent schedule
    // can make this pre-transaction snapshot stale and have its new row pruned.
    await reconcileMirror(withNativeAlarmIds: [])
  }

  @available(iOS 26.0, *)
  private func reconcileMirror(with _: [Alarm]) async {
    await reconcileMirror(withNativeAlarmIds: [])
  }

  @available(iOS 26.0, *)
  func reconcileMirror(withNativeAlarmIds _: [String]) async {
    await mirrorCoordinator.run {
      await self.reconcileMirrorInMirrorTransaction()
    }
  }

  @available(iOS 26.0, *)
  private func reconcileMirrorInMirrorTransaction() async {
    guard var mirrorSnapshot = try? loadMirrorSnapshot() else { return }
    do {
      // Observer payloads and launch notifications are wake hints only. Read
      // AlarmKit authority after entering the serialized transaction so a
      // schedule that completed while this reconciliation was queued cannot be
      // pruned by an older event snapshot.
      var authoritativeAlarms = try nativeClientForAlarmKit().inventory()
      if UserDefaults.standard.data(forKey: nativeAlarmReplacementJournalKey) != nil {
        mirrorSnapshot = try await reconcileReplacementJournal(
          in: mirrorSnapshot,
          nativeAlarms: authoritativeAlarms
        )
        // Journal reconciliation may retire one owned UUID. Prune against a
        // second fresh authoritative snapshot so recovery cannot resurrect or
        // retain the side it just retired.
        authoritativeAlarms = try nativeClientForAlarmKit().inventory()
      }
      let canonicalIds = try authoritativeNativeAlarmIds(
        authoritativeAlarms.map { $0.platformAlarmId },
        mirrorSnapshot: mirrorSnapshot
      )
      var reconciledMirror = mirrorSnapshot.normalized
      var reconciledPendingMirror = mirrorSnapshot.pendingNormalized
      let currentIds = Set(canonicalIds)
      let promotablePending = reconciledPendingMirror.filter {
        currentIds.contains($0.key) && $0.value.requiresNativeRestoration != true
      }
      for (platformAlarmId, record) in promotablePending {
        reconciledMirror[platformAlarmId] = record
        reconciledPendingMirror.removeValue(forKey: platformAlarmId)
      }
      try persistReconciledMirror(
        reconciledMirror: reconciledMirror,
        reconciledPendingMirror: reconciledPendingMirror,
        currentIds: currentIds,
        mirrorSnapshot: mirrorSnapshot
      )
    } catch {
      // Inventory read/validation, journal recovery, and persistence failures
      // all fail closed. Retain mirror and journal evidence for a later wake.
      return
    }
  }
}
