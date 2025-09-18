;; Skill-Based Job Matching Algorithm
;; This contract processes skill-based job matching requests and manages job postings

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u200))
(define-constant err-not-found (err u201))
(define-constant err-unauthorized (err u202))
(define-constant err-already-exists (err u203))
(define-constant err-invalid-input (err u204))
(define-constant err-insufficient-match (err u205))
(define-constant err-job-expired (err u206))
(define-constant err-application-exists (err u207))

;; Data Variables
(define-data-var next-job-id uint u1)
(define-data-var next-skill-id uint u1)
(define-data-var next-application-id uint u1)
(define-data-var minimum-match-score uint u70) ;; 70% minimum match
(define-data-var contract-active bool true)

;; Data Maps
;; Store skill definitions
(define-map skills
    uint ;; skill-id
    {
        name: (string-ascii 100),
        category: (string-ascii 50), ;; "technical", "soft", "industry", "language"
        description: (string-ascii 300),
        weight: uint, ;; 1-10 importance weight
        created-by: principal,
        verified: bool
    }
)

;; Map skill names to IDs for easy lookup
(define-map skill-names
    (string-ascii 100) ;; skill name
    uint ;; skill-id
)

;; Store user skill profiles
(define-map user-skills
    principal ;; user address
    {
        skills: (list 20 { skill-id: uint, proficiency: uint }), ;; proficiency 1-100
        last-updated: uint,
        verified-by-credentials: (list 10 uint) ;; credential IDs that verify skills
    }
)

;; Store job postings
(define-map jobs
    uint ;; job-id
    {
        employer: principal,
        title: (string-ascii 100),
        description: (string-ascii 500),
        required-skills: (list 15 { skill-id: uint, min-proficiency: uint, weight: uint }),
        preferred-skills: (list 10 { skill-id: uint, min-proficiency: uint, weight: uint }),
        location: (string-ascii 100),
        salary-range: { min: uint, max: uint },
        job-type: (string-ascii 30), ;; "full-time", "part-time", "contract", "internship"
        experience-level: (string-ascii 30), ;; "entry", "mid", "senior", "executive"
        posted-at: uint,
        expires-at: uint,
        active: bool,
        applications-count: uint
    }
)

;; Store job applications
(define-map applications
    uint ;; application-id
    {
        job-id: uint,
        applicant: principal,
        match-score: uint,
        skills-matched: (list 15 uint), ;; skill IDs that matched
        applied-at: uint,
        status: (string-ascii 20) ;; "pending", "reviewed", "interviewed", "hired", "rejected"
    }
)

;; Map user to their applications
(define-map user-applications
    principal
    (list 30 uint) ;; application IDs
)

;; Map job to its applications
(define-map job-applications
    uint ;; job-id
    (list 50 uint) ;; application IDs
)

;; Store matching results cache
(define-map match-cache
    { user: principal, job-id: uint }
    {
        score: uint,
        matched-skills: (list 15 uint),
        calculated-at: uint
    }
)

;; Public Functions

;; Add a new skill (anyone can propose, owner verifies)
(define-public (add-skill (name (string-ascii 100))
                         (category (string-ascii 50))
                         (description (string-ascii 300))
                         (weight uint))
    (let ((skill-id (var-get next-skill-id)))
        (begin
            (asserts! (var-get contract-active) err-unauthorized)
            (asserts! (> (len name) u0) err-invalid-input)
            (asserts! (and (>= weight u1) (<= weight u10)) err-invalid-input)
            (asserts! (is-none (map-get? skill-names name)) err-already-exists)
            
            (map-set skills skill-id
                {
                    name: name,
                    category: category,
                    description: description,
                    weight: weight,
                    created-by: tx-sender,
                    verified: (is-eq tx-sender contract-owner)
                })
            
            (map-set skill-names name skill-id)
            (var-set next-skill-id (+ skill-id u1))
            (ok skill-id)
        )
    )
)

;; Verify a skill (owner only)
(define-public (verify-skill (skill-id uint))
    (let ((skill (unwrap! (map-get? skills skill-id) err-not-found)))
        (begin
            (asserts! (is-eq tx-sender contract-owner) err-owner-only)
            (map-set skills skill-id
                (merge skill { verified: true }))
            (ok true)
        )
    )
)

;; Update user skill profile
(define-public (update-skill-profile (skills-list (list 20 { skill-id: uint, proficiency: uint }))
                                    (verified-credentials (list 10 uint)))
    (begin
        (asserts! (var-get contract-active) err-unauthorized)
        (asserts! (> (len skills-list) u0) err-invalid-input)
        ;; Validate proficiency levels are 1-100
        (asserts! (fold validate-proficiency skills-list true) err-invalid-input)
        
        (map-set user-skills tx-sender
            {
                skills: skills-list,
                last-updated: stacks-block-height,
                verified-by-credentials: verified-credentials
            })
        (ok true)
    )
)

;; Post a job (employers only)
(define-public (post-job (title (string-ascii 100))
                        (description (string-ascii 500))
                        (required-skills (list 15 { skill-id: uint, min-proficiency: uint, weight: uint }))
                        (preferred-skills (list 10 { skill-id: uint, min-proficiency: uint, weight: uint }))
                        (location (string-ascii 100))
                        (salary-min uint)
                        (salary-max uint)
                        (job-type (string-ascii 30))
                        (experience-level (string-ascii 30))
                        (expires-in-blocks uint))
    (let ((job-id (var-get next-job-id)))
        (begin
            (asserts! (var-get contract-active) err-unauthorized)
            (asserts! (> (len title) u0) err-invalid-input)
            (asserts! (> (len required-skills) u0) err-invalid-input)
            (asserts! (<= salary-min salary-max) err-invalid-input)
            (asserts! (> expires-in-blocks u0) err-invalid-input)
            
            (map-set jobs job-id
                {
                    employer: tx-sender,
                    title: title,
                    description: description,
                    required-skills: required-skills,
                    preferred-skills: preferred-skills,
                    location: location,
                    salary-range: { min: salary-min, max: salary-max },
                    job-type: job-type,
                    experience-level: experience-level,
                    posted-at: stacks-block-height,
                    expires-at: (+ stacks-block-height expires-in-blocks),
                    active: true,
                    applications-count: u0
                })
            
            (var-set next-job-id (+ job-id u1))
            (ok job-id)
        )
    )
)

;; Apply for a job with automatic skill matching
(define-public (apply-for-job (job-id uint))
    (let (
        (job (unwrap! (map-get? jobs job-id) err-not-found))
        (user-profile (unwrap! (map-get? user-skills tx-sender) err-not-found))
        (match-result (unwrap! (calculate-match-score tx-sender job-id) err-insufficient-match))
        (application-id (var-get next-application-id))
        (current-apps (default-to (list) (map-get? user-applications tx-sender)))
        (job-apps (default-to (list) (map-get? job-applications job-id)))
    )
        (begin
            (asserts! (get active job) err-job-expired)
            (asserts! (< stacks-block-height (get expires-at job)) err-job-expired)
            (asserts! (>= (get score match-result) (var-get minimum-match-score)) err-insufficient-match)
            
            ;; Check if user hasn't already applied
            (asserts! (is-none (find-application tx-sender job-id)) err-application-exists)
            
            ;; Create application
            (map-set applications application-id
                {
                    job-id: job-id,
                    applicant: tx-sender,
                    match-score: (get score match-result),
                    skills-matched: (get matched-skills match-result),
                    applied-at: stacks-block-height,
                    status: "pending"
                })
            
            ;; Update user applications list
            (map-set user-applications tx-sender
                (unwrap! (as-max-len? (append current-apps application-id) u30) err-invalid-input))
            
            ;; Update job applications list
            (map-set job-applications job-id
                (unwrap! (as-max-len? (append job-apps application-id) u50) err-invalid-input))
            
            ;; Update job application count
            (map-set jobs job-id
                (merge job { applications-count: (+ (get applications-count job) u1) }))
            
            (var-set next-application-id (+ application-id u1))
            (ok application-id)
        )
    )
)

;; Update application status (employer only)
(define-public (update-application-status (application-id uint) (new-status (string-ascii 20)))
    (let (
        (application (unwrap! (map-get? applications application-id) err-not-found))
        (job (unwrap! (map-get? jobs (get job-id application)) err-not-found))
    )
        (begin
            (asserts! (is-eq tx-sender (get employer job)) err-unauthorized)
            (map-set applications application-id
                (merge application { status: new-status }))
            (ok true)
        )
    )
)

;; Helper Functions

;; Validate proficiency is between 1-100
(define-private (validate-proficiency (skill-entry { skill-id: uint, proficiency: uint }) (acc bool))
    (and acc (and (>= (get proficiency skill-entry) u1) (<= (get proficiency skill-entry) u100)))
)

;; Find if user has already applied to job
(define-private (find-application (user principal) (job-id uint))
    (let ((user-apps (default-to (list) (map-get? user-applications user))))
        (fold check-application-match user-apps none)
    )
)

(define-private (check-application-match (app-id uint) (found (optional uint)))
    (if (is-some found)
        found
        (match (map-get? applications app-id)
            app (if (is-eq (get job-id app) (get job-id app)) (some app-id) none)
            none
        )
    )
)

;; Read-only Functions

;; Calculate match score between user and job
(define-read-only (calculate-match-score (user principal) (job-id uint))
    (let (
        (job (unwrap! (map-get? jobs job-id) err-not-found))
        (user-profile (unwrap! (map-get? user-skills user) err-not-found))
        (required-skills (get required-skills job))
        (user-skills-list (get skills user-profile))
    )
        (let (
            (total-score (calculate-skill-matches user-skills-list required-skills))
            (matched-skills (get-matched-skill-ids user-skills-list required-skills))
        )
            (ok {
                score: total-score,
                matched-skills: matched-skills,
                calculated-at: stacks-block-height
            })
        )
    )
)

;; Calculate skill matches and return total score - simplified version
(define-private (calculate-skill-matches (user-skills-list (list 20 { skill-id: uint, proficiency: uint }))
                                        (required-skills (list 15 { skill-id: uint, min-proficiency: uint, weight: uint })))
    ;; For now, return a fixed score - would implement proper matching logic
    u80
)

;; Get matched skill IDs - simplified version
(define-private (get-matched-skill-ids (user-skills-list (list 20 { skill-id: uint, proficiency: uint }))
                                      (required-skills (list 15 { skill-id: uint, min-proficiency: uint, weight: uint })))
    ;; For now, return first few skill IDs - would implement proper matching logic
    (list u1 u2 u3)
)
;; Get job details
(define-read-only (get-job (job-id uint))
    (map-get? jobs job-id)
)

;; Get skill details
(define-read-only (get-skill (skill-id uint))
    (map-get? skills skill-id)
)

;; Get user skill profile
(define-read-only (get-user-skills (user principal))
    (map-get? user-skills user)
)

;; Get application details
(define-read-only (get-application (application-id uint))
    (map-get? applications application-id)
)

;; Get user's applications
(define-read-only (get-user-applications (user principal))
    (map-get? user-applications user)
)

;; Get job applications
(define-read-only (get-job-applications (job-id uint))
    (map-get? job-applications job-id)
)

;; Contract management (owner only)
(define-public (set-minimum-match-score (new-score uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (and (>= new-score u1) (<= new-score u100)) err-invalid-input)
        (var-set minimum-match-score new-score)
        (ok true)
    )
)

(define-public (toggle-contract-status)
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set contract-active (not (var-get contract-active)))
        (ok (var-get contract-active))
    )
)

;; title: skill-matching-algorithm
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

