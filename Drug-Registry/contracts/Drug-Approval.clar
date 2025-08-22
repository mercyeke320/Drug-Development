;; Smart Drug Development Contract
;; A comprehensive contract for managing pharmaceutical drug development lifecycle

;; Error codes
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_DRUG_NOT_FOUND (err u101))
(define-constant ERR_INVALID_PHASE (err u102))
(define-constant ERR_INSUFFICIENT_FUNDS (err u103))
(define-constant ERR_ALREADY_EXISTS (err u104))
(define-constant ERR_INVALID_STATUS (err u105))
(define-constant ERR_NOT_APPROVED (err u106))
(define-constant ERR_TRIAL_ACTIVE (err u107))
(define-constant ERR_INVALID_INPUT (err u108))
(define-constant ERR_INVALID_PRINCIPAL (err u109))

;; Contract owner
(define-constant CONTRACT_OWNER tx-sender)

;; Drug development phases
(define-constant PHASE_DISCOVERY u0)
(define-constant PHASE_PRECLINICAL u1)
(define-constant PHASE_CLINICAL_1 u2)
(define-constant PHASE_CLINICAL_2 u3)
(define-constant PHASE_CLINICAL_3 u4)
(define-constant PHASE_REGULATORY u5)
(define-constant PHASE_APPROVED u6)

;; Trial statuses
(define-constant STATUS_PLANNED u0)
(define-constant STATUS_ACTIVE u1)
(define-constant STATUS_COMPLETED u2)
(define-constant STATUS_SUSPENDED u3)
(define-constant STATUS_TERMINATED u4)

;; Maximum values for validation
(define-constant MAX_PATENT_DURATION u5256000) ;; ~10 years in blocks
(define-constant MAX_PARTICIPANTS u100000)
(define-constant MAX_FUNDING_AMOUNT u1000000000000) ;; 1 trillion microSTX
(define-constant MIN_NAME_LENGTH u1)

;; Data structures
(define-map drugs
  { drug-id: uint }
  {
    name: (string-ascii 100),
    developer: principal,
    current-phase: uint,
    total-funding: uint,
    patent-expires: uint,
    regulatory-approved: bool,
    created-at: uint
  }
)

(define-map clinical-trials
  { trial-id: uint }
  {
    drug-id: uint,
    phase: uint,
    participants: uint,
    status: uint,
    start-block: uint,
    end-block: (optional uint),
    results: (optional (string-ascii 500)),
    cost: uint
  }
)

(define-map research-data
  { data-id: uint }
  {
    drug-id: uint,
    researcher: principal,
    data-hash: (buff 32),
    timestamp: uint,
    verified: bool
  }
)

(define-map funding-rounds
  { round-id: uint }
  {
    drug-id: uint,
    amount: uint,
    investor: principal,
    phase: uint,
    timestamp: uint
  }
)

(define-map regulatory-submissions
  { submission-id: uint }
  {
    drug-id: uint,
    submission-type: (string-ascii 50),
    submitted-at: uint,
    approved: bool,
    regulator: principal
  }
)

;; Counters
(define-data-var drug-counter uint u0)
(define-data-var trial-counter uint u0)
(define-data-var data-counter uint u0)
(define-data-var funding-counter uint u0)
(define-data-var submission-counter uint u0)

;; Authorized researchers and regulators
(define-map authorized-researchers principal bool)
(define-map authorized-regulators principal bool)

;; Initialize contract with owner as authorized
(map-set authorized-researchers CONTRACT_OWNER true)
(map-set authorized-regulators CONTRACT_OWNER true)

;; Input validation functions
(define-private (is-valid-principal (addr principal))
  (not (is-eq addr 'SP000000000000000000002Q6VF78))
)

(define-private (is-valid-string (str (string-ascii 100)))
  (> (len str) u0)
)

(define-private (is-valid-submission-type (str (string-ascii 50)))
  (> (len str) u0)
)

(define-private (is-valid-phase (phase uint))
  (and (>= phase PHASE_DISCOVERY) (<= phase PHASE_APPROVED))
)

(define-private (is-valid-trial-phase (phase uint))
  (and (>= phase PHASE_CLINICAL_1) (<= phase PHASE_CLINICAL_3))
)

(define-private (is-valid-patent-duration (duration uint))
  (and (> duration u0) (<= duration MAX_PATENT_DURATION))
)

(define-private (is-valid-participants (count uint))
  (and (> count u0) (<= count MAX_PARTICIPANTS))
)

(define-private (is-valid-amount (amount uint))
  (and (> amount u0) (<= amount MAX_FUNDING_AMOUNT))
)

(define-private (is-valid-drug-id (drug-id uint))
  (and (> drug-id u0) (<= drug-id (var-get drug-counter)))
)

(define-private (is-valid-trial-id (trial-id uint))
  (and (> trial-id u0) (<= trial-id (var-get trial-counter)))
)

(define-private (is-valid-data-id (data-id uint))
  (and (> data-id u0) (<= data-id (var-get data-counter)))
)

(define-private (is-valid-submission-id (submission-id uint))
  (and (> submission-id u0) (<= submission-id (var-get submission-counter)))
)

(define-private (is-non-zero-hash (hash (buff 32)))
  (not (is-eq hash 0x0000000000000000000000000000000000000000000000000000000000000000))
)

;; Authorization functions
(define-public (authorize-researcher (researcher principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (asserts! (is-valid-principal researcher) ERR_INVALID_PRINCIPAL)
    (ok (map-set authorized-researchers researcher true))
  )
)

(define-public (authorize-regulator (regulator principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (asserts! (is-valid-principal regulator) ERR_INVALID_PRINCIPAL)
    (ok (map-set authorized-regulators regulator true))
  )
)

;; Helper functions
(define-private (is-authorized-researcher (researcher principal))
  (default-to false (map-get? authorized-researchers researcher))
)

(define-private (is-authorized-regulator (regulator principal))
  (default-to false (map-get? authorized-regulators regulator))
)

;; Register new drug for development
(define-public (register-drug (name (string-ascii 100)) (patent-duration uint))
  (let
    (
      (drug-id (+ (var-get drug-counter) u1))
      (current-block block-height)
    )
    (asserts! (is-authorized-researcher tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (is-valid-string name) ERR_INVALID_INPUT)
    (asserts! (is-valid-patent-duration patent-duration) ERR_INVALID_INPUT)
    (asserts! (is-none (map-get? drugs { drug-id: drug-id })) ERR_ALREADY_EXISTS)
    
    (map-set drugs
      { drug-id: drug-id }
      {
        name: name,
        developer: tx-sender,
        current-phase: PHASE_DISCOVERY,
        total-funding: u0,
        patent-expires: (+ current-block patent-duration),
        regulatory-approved: false,
        created-at: current-block
      }
    )
    (var-set drug-counter drug-id)
    (ok drug-id)
  )
)

;; Add research data
(define-public (add-research-data (drug-id uint) (data-hash (buff 32)))
  (let
    (
      (data-id (+ (var-get data-counter) u1))
      (drug-info (unwrap! (map-get? drugs { drug-id: drug-id }) ERR_DRUG_NOT_FOUND))
    )
    (asserts! (is-authorized-researcher tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (is-valid-drug-id drug-id) ERR_INVALID_INPUT)
    (asserts! (is-non-zero-hash data-hash) ERR_INVALID_INPUT)
    
    (map-set research-data
      { data-id: data-id }
      {
        drug-id: drug-id,
        researcher: tx-sender,
        data-hash: data-hash,
        timestamp: block-height,
        verified: false
      }
    )
    (var-set data-counter data-id)
    (ok data-id)
  )
)

;; Verify research data
(define-public (verify-research-data (data-id uint))
  (let
    (
      (data-info (unwrap! (map-get? research-data { data-id: data-id }) ERR_DRUG_NOT_FOUND))
    )
    (asserts! (is-authorized-researcher tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (is-valid-data-id data-id) ERR_INVALID_INPUT)
    (asserts! (not (get verified data-info)) ERR_INVALID_STATUS)
    
    (map-set research-data
      { data-id: data-id }
      (merge data-info { verified: true })
    )
    (ok true)
  )
)

;; Start clinical trial
(define-public (start-clinical-trial (drug-id uint) (phase uint) (participants uint) (estimated-cost uint))
  (let
    (
      (trial-id (+ (var-get trial-counter) u1))
      (drug-info (unwrap! (map-get? drugs { drug-id: drug-id }) ERR_DRUG_NOT_FOUND))
    )
    (asserts! (is-authorized-researcher tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (is-eq (get developer drug-info) tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (is-valid-drug-id drug-id) ERR_INVALID_INPUT)
    (asserts! (is-valid-trial-phase phase) ERR_INVALID_PHASE)
    (asserts! (is-valid-participants participants) ERR_INVALID_INPUT)
    (asserts! (is-valid-amount estimated-cost) ERR_INVALID_INPUT)
    (asserts! (>= (get total-funding drug-info) estimated-cost) ERR_INSUFFICIENT_FUNDS)
    
    (map-set clinical-trials
      { trial-id: trial-id }
      {
        drug-id: drug-id,
        phase: phase,
        participants: participants,
        status: STATUS_ACTIVE,
        start-block: block-height,
        end-block: none,
        results: none,
        cost: estimated-cost
      }
    )
    (var-set trial-counter trial-id)
    (ok trial-id)
  )
)

;; Complete clinical trial with results
(define-public (complete-clinical-trial (trial-id uint) (results (string-ascii 500)))
  (let
    (
      (trial-info (unwrap! (map-get? clinical-trials { trial-id: trial-id }) ERR_DRUG_NOT_FOUND))
      (drug-info (unwrap! (map-get? drugs { drug-id: (get drug-id trial-info) }) ERR_DRUG_NOT_FOUND))
    )
    (asserts! (is-authorized-researcher tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (is-eq (get developer drug-info) tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (is-valid-trial-id trial-id) ERR_INVALID_INPUT)
    (asserts! (> (len results) u0) ERR_INVALID_INPUT)
    (asserts! (is-eq (get status trial-info) STATUS_ACTIVE) ERR_INVALID_STATUS)
    
    (map-set clinical-trials
      { trial-id: trial-id }
      (merge trial-info {
        status: STATUS_COMPLETED,
        end-block: (some block-height),
        results: (some results)
      })
    )
    (ok true)
  )
)

;; Add funding to drug development
(define-public (add-funding (drug-id uint) (amount uint))
  (let
    (
      (funding-id (+ (var-get funding-counter) u1))
      (drug-info (unwrap! (map-get? drugs { drug-id: drug-id }) ERR_DRUG_NOT_FOUND))
    )
    (asserts! (is-valid-drug-id drug-id) ERR_INVALID_INPUT)
    (asserts! (is-valid-amount amount) ERR_INVALID_INPUT)
    
    ;; Transfer STX to contract (in real implementation, you'd handle token transfers)
    (map-set funding-rounds
      { round-id: funding-id }
      {
        drug-id: drug-id,
        amount: amount,
        investor: tx-sender,
        phase: (get current-phase drug-info),
        timestamp: block-height
      }
    )
    
    ;; Update total funding
    (map-set drugs
      { drug-id: drug-id }
      (merge drug-info {
        total-funding: (+ (get total-funding drug-info) amount)
      })
    )
    
    (var-set funding-counter funding-id)
    (ok funding-id)
  )
)

;; Advance drug to next phase
(define-public (advance-phase (drug-id uint))
  (let
    (
      (drug-info (unwrap! (map-get? drugs { drug-id: drug-id }) ERR_DRUG_NOT_FOUND))
      (current-phase (get current-phase drug-info))
      (next-phase (+ current-phase u1))
    )
    (asserts! (is-authorized-researcher tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (is-eq (get developer drug-info) tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (is-valid-drug-id drug-id) ERR_INVALID_INPUT)
    (asserts! (<= next-phase PHASE_APPROVED) ERR_INVALID_PHASE)
    
    (map-set drugs
      { drug-id: drug-id }
      (merge drug-info { current-phase: next-phase })
    )
    (ok next-phase)
  )
)

;; Submit for regulatory approval
(define-public (submit-regulatory-approval (drug-id uint) (submission-type (string-ascii 50)))
  (let
    (
      (submission-id (+ (var-get submission-counter) u1))
      (drug-info (unwrap! (map-get? drugs { drug-id: drug-id }) ERR_DRUG_NOT_FOUND))
    )
    (asserts! (is-authorized-researcher tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (is-eq (get developer drug-info) tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (is-valid-drug-id drug-id) ERR_INVALID_INPUT)
    (asserts! (is-valid-submission-type submission-type) ERR_INVALID_INPUT)
    (asserts! (>= (get current-phase drug-info) PHASE_REGULATORY) ERR_INVALID_PHASE)
    
    (map-set regulatory-submissions
      { submission-id: submission-id }
      {
        drug-id: drug-id,
        submission-type: submission-type,
        submitted-at: block-height,
        approved: false,
        regulator: tx-sender
      }
    )
    (var-set submission-counter submission-id)
    (ok submission-id)
  )
)

;; Approve regulatory submission (only regulators)
(define-public (approve-regulatory-submission (submission-id uint))
  (let
    (
      (submission-info (unwrap! (map-get? regulatory-submissions { submission-id: submission-id }) ERR_DRUG_NOT_FOUND))
      (drug-info (unwrap! (map-get? drugs { drug-id: (get drug-id submission-info) }) ERR_DRUG_NOT_FOUND))
    )
    (asserts! (is-authorized-regulator tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (is-valid-submission-id submission-id) ERR_INVALID_INPUT)
    (asserts! (not (get approved submission-info)) ERR_INVALID_STATUS)
    
    ;; Approve submission
    (map-set regulatory-submissions
      { submission-id: submission-id }
      (merge submission-info {
        approved: true,
        regulator: tx-sender
      })
    )
    
    ;; Mark drug as regulatory approved
    (map-set drugs
      { drug-id: (get drug-id submission-info) }
      (merge drug-info {
        regulatory-approved: true,
        current-phase: PHASE_APPROVED
      })
    )
    (ok true)
  )
)

;; Read-only functions

(define-read-only (get-drug-info (drug-id uint))
  (map-get? drugs { drug-id: drug-id })
)

(define-read-only (get-trial-info (trial-id uint))
  (map-get? clinical-trials { trial-id: trial-id })
)

(define-read-only (get-research-data-info (data-id uint))
  (map-get? research-data { data-id: data-id })
)

(define-read-only (get-funding-info (round-id uint))
  (map-get? funding-rounds { round-id: round-id })
)

(define-read-only (get-submission-info (submission-id uint))
  (map-get? regulatory-submissions { submission-id: submission-id })
)

(define-read-only (get-drug-counter)
  (var-get drug-counter)
)

(define-read-only (get-trial-counter)
  (var-get trial-counter)
)

(define-read-only (is-drug-approved (drug-id uint))
  (match (map-get? drugs { drug-id: drug-id })
    drug-info (get regulatory-approved drug-info)
    false
  )
)

(define-read-only (get-drug-phase (drug-id uint))
  (match (map-get? drugs { drug-id: drug-id })
    drug-info (some (get current-phase drug-info))
    none
  )
)

(define-read-only (get-total-funding (drug-id uint))
  (match (map-get? drugs { drug-id: drug-id })
    drug-info (some (get total-funding drug-info))
    none
  )
)