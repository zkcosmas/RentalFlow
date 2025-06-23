;; RentalFlow - Basic Property Rental Contract (Stage 1)
;; Simple lease management with fixed rent payments

(define-constant PROPERTY_MANAGER tx-sender)
(define-constant ERR_ACCESS_FORBIDDEN (err u500))
(define-constant ERR_LEASE_NOT_FOUND (err u501))
(define-constant ERR_INSUFFICIENT_FUNDS (err u502))
(define-constant ERR_LEASE_EXISTS (err u503))
(define-constant ERR_INVALID_TERMS (err u504))

;; Basic lease agreements
(define-map property-leases
  { lease-id: uint }
  {
    landlord: principal,
    tenant: principal,
    monthly-rent: uint,
    lease-start: uint,
    lease-end: uint,
    security-deposit: uint,
    rent-paid: uint,
    active: bool
  }
)

;; Simple balance tracking
(define-map user-balances
  { user: principal }
  { balance: uint }
)

;; Lease counter
(define-data-var lease-counter uint u0)

;; Get current block height as timestamp
(define-read-only (get-current-time)
  block-height
)

;; Get user balance
(define-read-only (get-balance (user principal))
  (default-to u0 (get balance (map-get? user-balances { user: user })))
)

;; Get lease details
(define-read-only (get-lease (lease-id uint))
  (map-get? property-leases { lease-id: lease-id })
)

;; Deposit funds to user balance
(define-public (deposit-funds (amount uint))
  (let (
    (current-balance (get-balance tx-sender))
  )
  (map-set user-balances
    { user: tx-sender }
    { balance: (+ current-balance amount) }
  )
  (ok (+ current-balance amount)))
)

;; Withdraw funds from user balance
(define-public (withdraw-funds (amount uint))
  (let (
    (current-balance (get-balance tx-sender))
  )
  (if (>= current-balance amount)
    (begin
      (map-set user-balances
        { user: tx-sender }
        { balance: (- current-balance amount) }
      )
      (ok (- current-balance amount)))
    ERR_INSUFFICIENT_FUNDS))
)

;; Create a lease agreement
(define-public (create-lease 
  (tenant principal) 
  (monthly-rent uint) 
  (security-deposit uint)
  (lease-duration uint))
  (let (
    (lease-id (+ (var-get lease-counter) u1))
    (current-time (get-current-time))
    (lease-end-time (+ current-time lease-duration))
    (landlord-balance (get-balance tx-sender))
  )
  (asserts! (> monthly-rent u0) ERR_INVALID_TERMS)
  (asserts! (> security-deposit u0) ERR_INVALID_TERMS)
  (asserts! (> lease-duration u0) ERR_INVALID_TERMS)
  (asserts! (>= landlord-balance security-deposit) ERR_INSUFFICIENT_FUNDS)
  (asserts! (is-none (map-get? property-leases { lease-id: lease-id })) ERR_LEASE_EXISTS)
  
  ;; Hold security deposit
  (map-set user-balances
    { user: tx-sender }
    { balance: (- landlord-balance security-deposit) }
  )
  
  ;; Create lease
  (map-set property-leases
    { lease-id: lease-id }
    {
      landlord: tx-sender,
      tenant: tenant,
      monthly-rent: monthly-rent,
      lease-start: current-time,
      lease-end: lease-end-time,
      security-deposit: security-deposit,
      rent-paid: u0,
      active: true
    }
  )
  
  ;; Update counter
  (var-set lease-counter lease-id)
  
  (ok lease-id))
)

;; Pay rent (tenant pays monthly rent)
(define-public (pay-rent (lease-id uint))
  (match (map-get? property-leases { lease-id: lease-id })
    lease-data
    (let (
      (tenant (get tenant lease-data))
      (landlord (get landlord lease-data))
      (monthly-rent (get monthly-rent lease-data))
      (tenant-balance (get-balance tenant))
      (landlord-balance (get-balance landlord))
      (current-paid (get rent-paid lease-data))
    )
    (asserts! (is-eq tx-sender tenant) ERR_ACCESS_FORBIDDEN)
    (asserts! (get active lease-data) ERR_LEASE_NOT_FOUND)
    (asserts! (>= tenant-balance monthly-rent) ERR_INSUFFICIENT_FUNDS)
    
    ;; Transfer rent from tenant to landlord
    (map-set user-balances
      { user: tenant }
      { balance: (- tenant-balance monthly-rent) }
    )
    
    (map-set user-balances
      { user: landlord }
      { balance: (+ landlord-balance monthly-rent) }
    )
    
    ;; Update rent paid
    (map-set property-leases
      { lease-id: lease-id }
      (merge lease-data { rent-paid: (+ current-paid monthly-rent) })
    )
    
    (ok monthly-rent))
    ERR_LEASE_NOT_FOUND)
)

;; End lease and return security deposit
(define-public (end-lease (lease-id uint))
  (match (map-get? property-leases { lease-id: lease-id })
    lease-data
    (let (
      (landlord (get landlord lease-data))
      (tenant (get tenant lease-data))
      (security-deposit (get security-deposit lease-data))
      (tenant-balance (get-balance tenant))
    )
    (asserts! (is-eq tx-sender landlord) ERR_ACCESS_FORBIDDEN)
    (asserts! (get active lease-data) ERR_LEASE_NOT_FOUND)
    
    ;; Mark lease as inactive
    (map-set property-leases
      { lease-id: lease-id }
      (merge lease-data { active: false })
    )
    
    ;; Return security deposit to tenant
    (map-set user-balances
      { user: tenant }
      { balance: (+ tenant-balance security-deposit) }
    )
    
    (ok security-deposit))
    ERR_LEASE_NOT_FOUND)
)

;; Check if lease has expired
(define-read-only (is-lease-expired (lease-id uint))
  (match (map-get? property-leases { lease-id: lease-id })
    lease-data
    (let (
      (current-time (get-current-time))
      (lease-end (get lease-end lease-data))
    )
    (or (not (get active lease-data)) (>= current-time lease-end)))
    false)
)

;; Get total number of leases
(define-read-only (get-lease-count)
  (var-get lease-counter)
)