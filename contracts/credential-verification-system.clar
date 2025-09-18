;; Academic Credential Verification System
;; This contract manages the immutable storage and verification of academic achievements and certifications

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-already-exists (err u103))
(define-constant err-invalid-input (err u104))
(define-constant err-institution-not-verified (err u105))
(define-constant err-credential-revoked (err u106))

;; Data Variables
(define-data-var next-credential-id uint u1)
(define-data-var next-institution-id uint u1)
(define-data-var contract-active bool true)

;; Data Maps
;; Store verified institutions
(define-map institutions
    uint ;; institution-id
    {
        name: (string-ascii 100),
        country: (string-ascii 50),
        verification-status: bool,
        public-key: (buff 33),
        created-at: uint,
        credentials-issued: uint
    }
)

;; Map institution addresses to IDs
(define-map institution-addresses
    principal ;; institution address
    uint      ;; institution-id
)

;; Store academic credentials
(define-map credentials
    uint ;; credential-id
    {
        student-address: principal,
        institution-id: uint,
        credential-type: (string-ascii 50), ;; "degree", "certificate", "diploma"
        degree-level: (string-ascii 30),     ;; "bachelor", "master", "phd", "associate"
        field-of-study: (string-ascii 100),
        grade: (string-ascii 20),
        issue-date: uint,
        completion-date: uint,
        credential-hash: (buff 32),
        verification-status: bool,
        revoked: bool,
        metadata: (string-ascii 500)
    }
)

;; Map student addresses to their credential IDs
(define-map student-credentials
    principal ;; student address
    (list 50 uint) ;; list of credential IDs
)

;; Store credential verification requests
(define-map verification-requests
    uint ;; request-id
    {
        credential-id: uint,
        requester: principal,
        purpose: (string-ascii 200),
        requested-at: uint,
        status: (string-ascii 20) ;; "pending", "approved", "denied"
    }
)

(define-data-var next-verification-request-id uint u1)

;; Public Functions

;; Register a new institution
(define-public (register-institution (name (string-ascii 100)) 
                                   (country (string-ascii 50))
                                   (public-key (buff 33)))
    (let ((institution-id (var-get next-institution-id)))
        (begin
            (asserts! (var-get contract-active) err-unauthorized)
            (asserts! (> (len name) u0) err-invalid-input)
            (asserts! (> (len country) u0) err-invalid-input)
            (asserts! (is-none (map-get? institution-addresses tx-sender)) err-already-exists)
            
            (map-set institutions institution-id
                {
                    name: name,
                    country: country,
                    verification-status: false,
                    public-key: public-key,
                    created-at: stacks-block-height,
                    credentials-issued: u0
                })
            
            (map-set institution-addresses tx-sender institution-id)
            (var-set next-institution-id (+ institution-id u1))
            (ok institution-id)
        )
    )
)

;; Verify an institution (only contract owner)
(define-public (verify-institution (institution-id uint))
    (let ((institution (unwrap! (map-get? institutions institution-id) err-not-found)))
        (begin
            (asserts! (is-eq tx-sender contract-owner) err-owner-only)
            (map-set institutions institution-id
                (merge institution { verification-status: true }))
            (ok true)
        )
    )
)

;; Issue a credential (only verified institutions)
(define-public (issue-credential (student-address principal)
                                (credential-type (string-ascii 50))
                                (degree-level (string-ascii 30))
                                (field-of-study (string-ascii 100))
                                (grade (string-ascii 20))
                                (completion-date uint)
                                (credential-hash (buff 32))
                                (metadata (string-ascii 500)))
    (let (
        (institution-id (unwrap! (map-get? institution-addresses tx-sender) err-unauthorized))
        (institution (unwrap! (map-get? institutions institution-id) err-not-found))
        (credential-id (var-get next-credential-id))
        (current-credentials (default-to (list) (map-get? student-credentials student-address)))
    )
        (begin
            (asserts! (get verification-status institution) err-institution-not-verified)
            (asserts! (> (len credential-type) u0) err-invalid-input)
            (asserts! (> (len field-of-study) u0) err-invalid-input)
            (asserts! (<= completion-date stacks-block-height) err-invalid-input)
            
            ;; Store the credential
            (map-set credentials credential-id
                {
                    student-address: student-address,
                    institution-id: institution-id,
                    credential-type: credential-type,
                    degree-level: degree-level,
                    field-of-study: field-of-study,
                    grade: grade,
                    issue-date: stacks-block-height,
                    completion-date: completion-date,
                    credential-hash: credential-hash,
                    verification-status: true,
                    revoked: false,
                    metadata: metadata
                })
            
            ;; Update student's credential list
            (map-set student-credentials student-address
                (unwrap! (as-max-len? (append current-credentials credential-id) u50) err-invalid-input))
            
            ;; Update institution's credential count
            (map-set institutions institution-id
                (merge institution { credentials-issued: (+ (get credentials-issued institution) u1) }))
            
            (var-set next-credential-id (+ credential-id u1))
            (ok credential-id)
        )
    )
)

;; Revoke a credential (only issuing institution)
(define-public (revoke-credential (credential-id uint))
    (let (
        (credential (unwrap! (map-get? credentials credential-id) err-not-found))
        (institution-id (unwrap! (map-get? institution-addresses tx-sender) err-unauthorized))
    )
        (begin
            (asserts! (is-eq (get institution-id credential) institution-id) err-unauthorized)
            (asserts! (not (get revoked credential)) err-credential-revoked)
            
            (map-set credentials credential-id
                (merge credential { revoked: true }))
            (ok true)
        )
    )
)

;; Request credential verification
(define-public (request-verification (credential-id uint) (purpose (string-ascii 200)))
    (let ((request-id (var-get next-verification-request-id)))
        (begin
            (asserts! (is-some (map-get? credentials credential-id)) err-not-found)
            (asserts! (> (len purpose) u0) err-invalid-input)
            
            (map-set verification-requests request-id
                {
                    credential-id: credential-id,
                    requester: tx-sender,
                    purpose: purpose,
                    requested-at: stacks-block-height,
                    status: "pending"
                })
            
            (var-set next-verification-request-id (+ request-id u1))
            (ok request-id)
        )
    )
)

;; Approve verification request (credential owner only)
(define-public (approve-verification (request-id uint))
    (let (
        (request (unwrap! (map-get? verification-requests request-id) err-not-found))
        (credential (unwrap! (map-get? credentials (get credential-id request)) err-not-found))
    )
        (begin
            (asserts! (is-eq tx-sender (get student-address credential)) err-unauthorized)
            (asserts! (is-eq (get status request) "pending") err-invalid-input)
            
            (map-set verification-requests request-id
                (merge request { status: "approved" }))
            (ok true)
        )
    )
)

;; Read-only functions

;; Get credential details
(define-read-only (get-credential (credential-id uint))
    (map-get? credentials credential-id)
)

;; Get institution details
(define-read-only (get-institution (institution-id uint))
    (map-get? institutions institution-id)
)

;; Get student's credentials
(define-read-only (get-student-credentials (student-address principal))
    (map-get? student-credentials student-address)
)

;; Verify credential authenticity
(define-read-only (verify-credential (credential-id uint))
    (match (map-get? credentials credential-id)
        credential (let 
            ((institution (unwrap! (map-get? institutions (get institution-id credential)) (err u404))))
            (ok {
                valid: (and 
                    (get verification-status credential)
                    (not (get revoked credential))
                    (get verification-status institution)
                ),
                credential: credential,
                institution: institution
            })
        )
        err-not-found
    )
)

;; Get verification request details
(define-read-only (get-verification-request (request-id uint))
    (map-get? verification-requests request-id)
)

;; Get total credentials issued by institution
(define-read-only (get-institution-stats (institution-id uint))
    (match (map-get? institutions institution-id)
        institution (ok {
            name: (get name institution),
            credentials-issued: (get credentials-issued institution),
            verification-status: (get verification-status institution)
        })
        err-not-found
    )
)

;; Contract management (owner only)
(define-public (toggle-contract-status)
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set contract-active (not (var-get contract-active)))
        (ok (var-get contract-active))
    )
)

;; title: credential-verification-system
;; version:
;; summary:
;; description:

;; traits
;;

;; token definitions
;;

;; constants
;;

;; data vars
;;

;; data maps
;;

;; public functions
;;

;; read only functions
;;

;; private functions
;;

