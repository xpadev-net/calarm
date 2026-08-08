import Foundation

extension AlarmKitBridge {
  func loadReservationAuthorities() throws -> [String: ReservationAuthorityRecord] {
    guard let data = UserDefaults.standard.data(forKey: nativeAlarmReservationAuthorityKey)
    else { return [:] }
    let ledger = try JSONDecoder().decode(ReservationAuthorityLedger.self, from: data)
    guard ledger.version == nativeAlarmReservationAuthorityVersion else {
      throw MirrorValidationError.invalid
    }
    var occurrences = Set<String>()
    var platformAlarmIds = Set<String>()
    for (key, record) in ledger.reservations {
      let hasLegacyConfiguration = record.hasLegacyConfigurationGap
      let hasCompleteConfiguration = record.scheduledAt != nil
        && record.targetAt != nil
        && record.soundId?.isEmpty == false
        && record.vibrationEnabled != nil
      guard key == record.reservationId,
        !record.reservationId.isEmpty,
        !record.occurrenceId.isEmpty,
        !record.wakePlanId.isEmpty,
        record.reservationGeneration >= 0,
        (try? canonicalPlatformAlarmId(record.platformAlarmId)) == record.platformAlarmId,
        occurrences.insert(record.occurrenceId).inserted,
        platformAlarmIds.insert(record.platformAlarmId).inserted,
        hasLegacyConfiguration || hasCompleteConfiguration
      else { throw MirrorValidationError.invalid }
    }
    return ledger.reservations
  }

  func saveReservationAuthorities(
    _ authorities: [String: ReservationAuthorityRecord]
  ) throws {
    let ledger = ReservationAuthorityLedger(
      version: nativeAlarmReservationAuthorityVersion,
      reservations: authorities
    )
    UserDefaults.standard.set(
      try JSONEncoder().encode(ledger),
      forKey: nativeAlarmReservationAuthorityKey
    )
  }

  func validateAuthorityConsistency(_ snapshot: MirrorSnapshot) throws {
    var authorities = try loadReservationAuthorities()
    var didAddLegacyAuthority = false
    for record in Array(snapshot.normalized.values) + Array(snapshot.pendingNormalized.values) {
      guard let authority = authorities[record.reservationId] else {
        guard !authorities.values.contains(where: { $0.occurrenceId == record.occurrenceId })
        else { throw MirrorValidationError.invalid }
        authorities[record.reservationId] = ReservationAuthorityRecord(
          record: record,
          state: .active
        )
        didAddLegacyAuthority = true
        continue
      }
      guard authority.wakePlanId == record.wakePlanId,
        authority.reservationGeneration >= record.generation
      else { throw MirrorValidationError.invalid }
      if authority.reservationGeneration == record.generation {
        guard authority.occurrenceId == record.occurrenceId else {
          throw MirrorValidationError.invalid
        }
      }
    }
    if didAddLegacyAuthority {
      try saveReservationAuthorities(authorities)
    }
  }

  func admitScheduleGeneration(
    _ request: ScheduleRequest,
    platformAlarmId: String,
    snapshot: MirrorSnapshot
  ) throws {
    if isNativeSmokeTestReservation(request) { return }
    guard request.reservationGeneration >= 0 else {
      throw ReservationAuthorityError.invalidRequest
    }
    var authorities = try loadReservationAuthorities()
    if authorities.values.contains(where: {
      $0.occurrenceId == request.occurrenceId && $0.reservationId != request.reservationId
    }) || snapshot.normalized.values.contains(where: {
      $0.occurrenceId == request.occurrenceId && $0.reservationId != request.reservationId
    }) || snapshot.pendingNormalized.values.contains(where: {
      $0.occurrenceId == request.occurrenceId && $0.reservationId != request.reservationId
    }) {
      throw ReservationAuthorityError.invalidRequest
    }
    let activeRecords = snapshot.normalized.values.filter {
      $0.reservationId == request.reservationId
    } + snapshot.pendingNormalized.values.filter {
      $0.reservationId == request.reservationId
    }
    guard activeRecords.count <= 1 else { throw MirrorValidationError.invalid }

    if let authority = authorities[request.reservationId] {
      guard authority.wakePlanId == request.wakePlanId else {
        throw ReservationAuthorityError.invalidRequest
      }
      guard request.reservationGeneration >= authority.reservationGeneration else {
        throw ReservationAuthorityError.invalidRequest
      }
      if request.reservationGeneration == authority.reservationGeneration {
        guard authority.state == .active else {
          throw ReservationAuthorityError.invalidRequest
        }
        if !authority.matches(request) {
          guard authority.hasLegacyConfigurationGap,
            authority.occurrenceId == request.occurrenceId
          else { throw ReservationAuthorityError.invalidRequest }
          authorities[request.reservationId] = ReservationAuthorityRecord(
            request: request,
            platformAlarmId: authority.platformAlarmId,
            state: .active
          )
          try saveReservationAuthorities(authorities)
        }
        return
      }
    } else if let active = activeRecords.first {
      guard active.wakePlanId == request.wakePlanId,
        request.reservationGeneration >= active.generation
      else { throw ReservationAuthorityError.invalidRequest }
      if request.reservationGeneration == active.generation,
        active.scheduleRequest() != nil,
        !active.matches(request)
      {
        throw ReservationAuthorityError.invalidRequest
      }
    } else if request.reservationGeneration != 0 {
      // A non-zero first sighting has no durable predecessor proving that it
      // belongs to this reservation. Fail closed rather than invent history.
      throw ReservationAuthorityError.invalidRequest
    }

    authorities[request.reservationId] = ReservationAuthorityRecord(
      request: request,
      platformAlarmId: platformAlarmId,
      state: .active
    )
    try saveReservationAuthorities(authorities)
  }

  func updateScheduleAuthorityPlatform(
    _ request: ScheduleRequest,
    platformAlarmId: String
  ) throws {
    if isNativeSmokeTestReservation(request) { return }
    var authorities = try loadReservationAuthorities()
    guard let authority = authorities[request.reservationId],
      authority.state == .active,
      authority.matches(request)
    else { throw MirrorValidationError.invalid }
    authorities[request.reservationId] = ReservationAuthorityRecord(
      request: request,
      platformAlarmId: platformAlarmId,
      state: .active
    )
    try saveReservationAuthorities(authorities)
  }

  func persistRetirement(_ record: AlarmMirrorRecord) throws {
    var authorities = try loadReservationAuthorities()
    if let authority = authorities[record.reservationId] {
      guard authority.wakePlanId == record.wakePlanId,
        authority.reservationGeneration >= record.generation
      else { throw MirrorValidationError.invalid }
      if authority.reservationGeneration == record.generation {
        guard authority.occurrenceId == record.occurrenceId else {
          throw MirrorValidationError.invalid
        }
        authorities[record.reservationId] = authority.retiring()
      }
    } else {
      authorities[record.reservationId] = ReservationAuthorityRecord(record: record, state: .retired)
    }
    try saveReservationAuthorities(authorities)
  }
}

enum ReservationAuthorityState: String, Codable {
  case active
  case retired
}

struct ReservationAuthorityRecord: Codable, Equatable {
  let reservationId: String
  let reservationGeneration: Int
  let occurrenceId: String
  let wakePlanId: String
  let platformAlarmId: String
  let scheduledAt: Date?
  let targetAt: Date?
  let soundId: String?
  let vibrationEnabled: Bool?
  let state: ReservationAuthorityState

  init(request: ScheduleRequest, platformAlarmId: String, state: ReservationAuthorityState) {
    reservationId = request.reservationId
    reservationGeneration = request.reservationGeneration
    occurrenceId = request.occurrenceId
    wakePlanId = request.wakePlanId
    self.platformAlarmId = platformAlarmId
    scheduledAt = request.scheduledAt
    targetAt = request.targetAt
    soundId = request.soundId
    vibrationEnabled = request.vibrationEnabled
    self.state = state
  }

  init(record: AlarmMirrorRecord, state: ReservationAuthorityState) {
    reservationId = record.reservationId
    reservationGeneration = record.generation
    occurrenceId = record.occurrenceId
    wakePlanId = record.wakePlanId
    platformAlarmId = record.platformAlarmId
    scheduledAt = record.scheduledAt
    targetAt = record.targetAt
    soundId = record.soundId
    vibrationEnabled = record.vibrationEnabled
    self.state = state
  }

  func matches(_ request: ScheduleRequest) -> Bool {
    reservationId == request.reservationId
      && reservationGeneration == request.reservationGeneration
      && occurrenceId == request.occurrenceId
      && wakePlanId == request.wakePlanId
      && scheduledAt == request.scheduledAt
      && targetAt == request.targetAt
      && soundId == request.soundId
      && vibrationEnabled == request.vibrationEnabled
  }

  var hasLegacyConfigurationGap: Bool {
    scheduledAt == nil
      && targetAt == nil
      && soundId == nil
      && vibrationEnabled == nil
  }

  func matchesCancellation(
    occurrenceId: String,
    reservationId: String,
    reservationGeneration: Int,
    platformAlarmId: String
  ) -> Bool {
    self.reservationId == reservationId
      && self.reservationGeneration == reservationGeneration
      && self.occurrenceId == occurrenceId
      && self.platformAlarmId == platformAlarmId
  }

  func retiring() -> ReservationAuthorityRecord {
    ReservationAuthorityRecord(
      reservationId: reservationId,
      reservationGeneration: reservationGeneration,
      occurrenceId: occurrenceId,
      wakePlanId: wakePlanId,
      platformAlarmId: platformAlarmId,
      scheduledAt: scheduledAt,
      targetAt: targetAt,
      soundId: soundId,
      vibrationEnabled: vibrationEnabled,
      state: .retired
    )
  }

  private init(
    reservationId: String,
    reservationGeneration: Int,
    occurrenceId: String,
    wakePlanId: String,
    platformAlarmId: String,
    scheduledAt: Date?,
    targetAt: Date?,
    soundId: String?,
    vibrationEnabled: Bool?,
    state: ReservationAuthorityState
  ) {
    self.reservationId = reservationId
    self.reservationGeneration = reservationGeneration
    self.occurrenceId = occurrenceId
    self.wakePlanId = wakePlanId
    self.platformAlarmId = platformAlarmId
    self.scheduledAt = scheduledAt
    self.targetAt = targetAt
    self.soundId = soundId
    self.vibrationEnabled = vibrationEnabled
    self.state = state
  }
}

private struct ReservationAuthorityLedger: Codable {
  let version: Int
  let reservations: [String: ReservationAuthorityRecord]
}

enum ReservationAuthorityError: Error {
  case invalidRequest
}
