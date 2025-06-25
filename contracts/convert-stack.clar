;; convert-stack.clar
;; BulletProof Convert Stack

;; This contract manages the certification and verification of smart contracts on the Stacks blockchain.
;; It provides functionality for:
;; 1. Registering and managing qualified auditors
;; 2. Submitting contracts for certification
;; 3. Issuing certifications with metadata
;; 4. Verifying contract certification status
;; 5. Managing auditor reputation and trust scores

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ALREADY-REGISTERED (err u101))
(define-constant ERR-NOT-REGISTERED (err u102))
(define-constant ERR-INVALID-RATING (err u103))
(define-constant ERR-ALREADY-CERTIFIED (err u104))
(define-constant ERR-NOT-CERTIFIED (err u105))
(define-constant ERR-INVALID-STATUS (err u106))
(define-constant ERR-INVALID-PARAMETERS (err u107))
(define-constant ERR-CONTRACT-NOT-FOUND (err u108))

;; Data structures

;; Admin control
(define-data-var contract-owner principal tx-sender)

;; Auditor registry: maps auditor principal to their details and status
(define-map auditors
  principal
  {
    name: (string-ascii 64),
    company: (string-ascii 64),
    website: (string-ascii 128),
    reputation-score: uint,
    certification-count: uint,
    status: (string-ascii 10), ;; "active", "inactive", "probation", "suspended"
    approved-at: uint
  }
)

;; Certification requests made by contract owners
(define-map certification-requests
  {
    contract-id: principal, ;; contract principal
    version: (string-ascii 16)
  }
  {
    owner: principal,
    description: (string-ascii 256),
    repository-url: (string-ascii 128),
    request-time: uint,
    status: (string-ascii 10) ;; "pending", "in-review", "certified", "rejected"
  }
)

;; Certifications issued by auditors
(define-map certifications
  {
    contract-id: principal,
    version: (string-ascii 16)
  }
  {
    auditor: principal,
    security-rating: uint, ;; 1-10 rating
    audit-report-url: (string-ascii 128),
    certification-time: uint,
    valid-until: uint, ;; optional expiration timestamp
    notes: (string-ascii 256)
  }
)

;; Auditor applications tracking
(define-map auditor-applications
  principal
  {
    name: (string-ascii 64),
    company: (string-ascii 64),
    website: (string-ascii 128),
    credentials: (string-ascii 256),
    application-time: uint
  }
)

;; Contract certification history (append-only list implemented as map with counter)
(define-map certification-history
  { 
    contract-id: principal,
    index: uint 
  }
  {
    version: (string-ascii 16),
    auditor: principal,
    security-rating: uint,
    certification-time: uint
  }
)

;; Counter to track the number of certifications per contract
(define-map certification-count principal uint)

;; Global platform statistics
(define-data-var total-auditors uint u0)
(define-data-var total-certifications uint u0)
(define-data-var total-certified-contracts uint u0)

;; Private functions

;; Check if caller is the contract owner
(define-private (is-contract-owner)
  (is-eq tx-sender (var-get contract-owner))
)

;; Check if caller is a registered and active auditor
(define-private (is-active-auditor (auditor principal))
  (match (map-get? auditors auditor)
    auditor-data (is-eq (get status auditor-data) "active")
    false
  )
)

;; Update the certification count for a contract
(define-private (update-certification-count (contract-id principal))
  (let ((current-count (default-to u0 (map-get? certification-count contract-id))))
    (map-set certification-count contract-id (+ current-count u1))
    (+ current-count u1)
  )
)

;; Add a certification to the contract history
(define-private (add-certification-history 
                  (contract-id principal) 
                  (version (string-ascii 16)) 
                  (auditor principal) 
                  (security-rating uint))
  (let ((index (update-certification-count contract-id)))
    (map-set certification-history
      { contract-id: contract-id, index: index }
      {
        version: version,
        auditor: auditor,
        security-rating: security-rating,
        certification-time: block-height
      }
    )
  )
)

;; Read-only functions

;; Check if a contract is certified
(define-read-only (is-contract-certified (contract-id principal) (version (string-ascii 16)))
  (is-some (map-get? certifications { contract-id: contract-id, version: version }))
)

;; Get auditor details
(define-read-only (get-auditor-details (auditor principal))
  (map-get? auditors auditor)
)

;; Get certification details for a contract
(define-read-only (get-certification-details (contract-id principal) (version (string-ascii 16)))
  (map-get? certifications { contract-id: contract-id, version: version })
)

;; Get certification request status
(define-read-only (get-certification-request (contract-id principal) (version (string-ascii 16)))
  (map-get? certification-requests { contract-id: contract-id, version: version })
)

;; Get certification history for a contract
(define-read-only (get-certification-history (contract-id principal) (index uint))
  (map-get? certification-history { contract-id: contract-id, index: index })
)

;; Get total certification count for a contract
(define-read-only (get-total-certifications-for-contract (contract-id principal))
  (default-to u0 (map-get? certification-count contract-id))
)

;; Get platform statistics
(define-read-only (get-platform-statistics)
  {
    total-auditors: (var-get total-auditors),
    total-certifications: (var-get total-certifications),
    total-certified-contracts: (var-get total-certified-contracts)
  }
)

;; Public functions

;; Transfer contract ownership
(define-public (transfer-ownership (new-owner principal))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (ok (var-set contract-owner new-owner))
  )
)

;; Apply to become an auditor
(define-public (apply-as-auditor
                (name (string-ascii 64))
                (company (string-ascii 64))
                (website (string-ascii 128))
                (credentials (string-ascii 256)))
  (begin
    (asserts! (is-none (map-get? auditor-applications tx-sender)) ERR-ALREADY-REGISTERED)
    (asserts! (is-none (map-get? auditors tx-sender)) ERR-ALREADY-REGISTERED)
    
    (map-set auditor-applications tx-sender
      {
        name: name,
        company: company,
        website: website,
        credentials: credentials,
        application-time: block-height
      }
    )
    (ok true)
  )
)

;; Approve an auditor application (only contract owner)
(define-public (approve-auditor (auditor principal))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (is-some (map-get? auditor-applications auditor)) ERR-NOT-REGISTERED)
    (asserts! (is-none (map-get? auditors auditor)) ERR-ALREADY-REGISTERED)
    
    (let ((application (unwrap! (map-get? auditor-applications auditor) ERR-NOT-REGISTERED)))
      (map-set auditors auditor
        {
          name: (get name application),
          company: (get company application),
          website: (get website application),
          reputation-score: u5, ;; Initial mid-level reputation score
          certification-count: u0,
          status: "active",
          approved-at: block-height
        }
      )
      (var-set total-auditors (+ (var-get total-auditors) u1))
      (map-delete auditor-applications auditor)
      (ok true)
    )
  )
)

;; Submit a contract for certification
(define-public (request-certification 
                (contract-id principal) 
                (version (string-ascii 16)) 
                (description (string-ascii 256))
                (repository-url (string-ascii 128)))
  (begin
    (asserts! (is-none (map-get? certification-requests 
                          { contract-id: contract-id, version: version })) 
              ERR-ALREADY-REGISTERED)
    
    (map-set certification-requests
      { contract-id: contract-id, version: version }
      {
        owner: tx-sender,
        description: description,
        repository-url: repository-url,
        request-time: block-height,
        status: "pending"
      }
    )
    (ok true)
  )
)


;; Public verification endpoint that any user can call to check if a contract is certified
(define-public (verify-contract (contract-id principal) (version (string-ascii 16)))
  (ok (is-contract-certified contract-id version))
)

;; Public endpoint to get detailed verification information for a contract
(define-public (get-verification-info (contract-id principal) (version (string-ascii 16)))
  (match (map-get? certifications { contract-id: contract-id, version: version })
    cert-data
      (let ((auditor-data (default-to 
                            { 
                              name: "", company: "", website: "", reputation-score: u0,
                              certification-count: u0, status: "", approved-at: u0
                            }
                            (map-get? auditors (get auditor cert-data)))))
        (ok {
          certified: true,
          auditor: (get auditor cert-data),
          auditor-name: (get name auditor-data),
          auditor-company: (get company auditor-data),
          security-rating: (get security-rating cert-data),
          certification-time: (get certification-time cert-data),
          valid-until: (get valid-until cert-data),
          auditor-reputation: (get reputation-score auditor-data)
        }))
    (ok { certified: false, auditor: tx-sender, auditor-name: "", auditor-company: "",
          security-rating: u0, certification-time: u0, valid-until: u0, auditor-reputation: u0 })
  )
)