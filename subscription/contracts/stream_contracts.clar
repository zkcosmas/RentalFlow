;; RentalFlow - Property & Asset Streaming Payments Contract
;; Enables continuous rental payments with real-time property usage billing

(define-constant PROPERTY_MANAGER tx-sender)
(define-constant ERR_ACCESS_FORBIDDEN (err u500))
(define-constant ERR_LEASE_NOT_FOUND (err u501))
(define-constant ERR_INSUFFICIENT_SECURITY (err u502))
(define-constant ERR_LEASE_ACTIVE (err u503))
(define-constant ERR_INVALID_TERMS (err u504))
(define-constant ERR_TENANCY_ENDED (err u505))
(define-constant ERR_RENT_FROZEN (err u506))

;; Property lease agreements
(define-map property-leases
  { lease-id: uint }
  {
    landlord: principal,
    tenant: principal,
    rent-per-second: uint,       ;; Rental cost per second of occupancy
    lease-commencement: uint,    ;; When lease period started
    lease-expiration: (optional uint), ;; Optional lease end date
    security-deposit: uint,      ;; Total security deposit held
    rent-collected: uint,        ;; Amount already collected by landlord
    lease-valid: bool,           ;; Lease agreement status
    rent-collection-paused: bool, ;; Pause rent collection
    pause-timestamp: (optional uint) ;; When rent collection was paused
  }
)

;; Track security deposits and balances
(define-map security-vaults
  { vault-owner: principal }
  { vault-balance: uint }
)

;; Track lease counter
(define-data-var lease-counter uint u0)

;; Track property and tenancy statistics
(define-map property-statistics
  { property-owner: principal }
  { properties-managed: uint, active-tenancies: uint }
)

;; Map property owners to their lease IDs
(define-map landlord-property-portfolio
  { landlord: principal, property-index: uint }
  { lease-id: uint }
)

(define-map tenant-rental-history
  { tenant: principal, tenancy-index: uint }
  { lease-id: uint }
)

;; Get current time for calculations
(define-read-only (get-timestamp)
  block-height
)

;; Get security vault balance
(define-read-only (get-vault-balance (vault-owner principal))
  (default-to u0 (get vault-balance (map-get? security-vaults { vault-owner: vault-owner })))
)

;; Get lease agreement details
(define-read-only (get-lease-agreement (lease-id uint))
  (map-get? property-leases { lease-id: lease-id })
)

;; Calculate collectible rent amount
(define-read-only (calculate-collectible-rent (lease-id uint))
  (match (map-get? property-leases { lease-id: lease-id })
    lease-data
    (let (
      (current-timestamp (get-timestamp))
      (commencement-time (get lease-commencement lease-data))
      (expiration-time (get lease-expiration lease-data))
      (rate (get rent-per-second lease-data))
      (collected (get rent-collected lease-data))
      (security (get security-deposit lease-data))
      (valid (get lease-valid lease-data))
      (paused (get rent-collection-paused lease-data))
      (pause-time (get pause-timestamp lease-data))
    )
    (if (and valid (not paused))
      (let (
        (effective-expiration (match expiration-time
          some-expiration some-expiration
          current-timestamp))
        (actual-expiration (if (> effective-expiration current-timestamp) current-timestamp effective-expiration))
        (occupancy-duration (if (>= actual-expiration commencement-time) (- actual-expiration commencement-time) u0))
        (total-rent-due (* occupancy-duration rate))
        (collectible (if (> total-rent-due collected) (- total-rent-due collected) u0))
        (max-collectible (if (> security collected) (- security collected) u0))
      )
      (if (< collectible max-collectible) collectible max-collectible))
      u0))
    u0)
)

;; Deposit funds to security vault
(define-public (deposit-security (amount uint))
  (let (
    (current-vault (get-vault-balance tx-sender))
    (new-vault-balance (+ current-vault amount))
  )
  (map-set security-vaults
    { vault-owner: tx-sender }
    { vault-balance: new-vault-balance }
  )
  (ok new-vault-balance))
)

;; Withdraw funds from security vault
(define-public (withdraw-security (amount uint))
  (let (
    (current-vault (get-vault-balance tx-sender))
  )
  (if (>= current-vault amount)
    (begin
      (map-set security-vaults
        { vault-owner: tx-sender }
        { vault-balance: (- current-vault amount) }
      )
      (ok (- current-vault amount)))
    ERR_INSUFFICIENT_SECURITY))
)

;; Execute lease agreement
(define-public (execute-lease 
  (tenant principal) 
  (rent-per-second uint) 
  (security-amount uint)
  (lease-term (optional uint)))
  (let (
    (lease-id (+ (var-get lease-counter) u1))
    (landlord-vault (get-vault-balance tx-sender))
    (current-timestamp (get-timestamp))
    (expiration-time (match lease-term
      some-term (some (+ current-timestamp some-term))
      none))
    (landlord-stats (default-to { properties-managed: u0, active-tenancies: u0 } 
                   (map-get? property-statistics { property-owner: tx-sender })))
    (tenant-stats (default-to { properties-managed: u0, active-tenancies: u0 } 
                      (map-get? property-statistics { property-owner: tenant })))
  )
  (asserts! (> rent-per-second u0) ERR_INVALID_TERMS)
  (asserts! (> security-amount u0) ERR_INVALID_TERMS)
  (asserts! (>= landlord-vault security-amount) ERR_INSUFFICIENT_SECURITY)
  (asserts! (is-none (map-get? property-leases { lease-id: lease-id })) ERR_LEASE_ACTIVE)
  
  ;; Hold security deposit from landlord vault
  (map-set security-vaults
    { vault-owner: tx-sender }
    { vault-balance: (- landlord-vault security-amount) }
  )
  
  ;; Create lease agreement
  (map-set property-leases
    { lease-id: lease-id }
    {
      landlord: tx-sender,
      tenant: tenant,
      rent-per-second: rent-per-second,
      lease-commencement: current-timestamp,
      lease-expiration: expiration-time,
      security-deposit: security-amount,
      rent-collected: u0,
      lease-valid: true,
      rent-collection-paused: false,
      pause-timestamp: none
    }
  )
  
  ;; Update lease counter
  (var-set lease-counter lease-id)
  
  ;; Update property mappings
  (map-set landlord-property-portfolio
    { landlord: tx-sender, property-index: (get properties-managed landlord-stats) }
    { lease-id: lease-id }
  )
  
  (map-set tenant-rental-history
    { tenant: tenant, tenancy-index: (get active-tenancies tenant-stats) }
    { lease-id: lease-id }
  )
  
  ;; Update property statistics
  (map-set property-statistics
    { property-owner: tx-sender }
    { properties-managed: (+ (get properties-managed landlord-stats) u1), 
      active-tenancies: (get active-tenancies landlord-stats) }
  )
  
  (map-set property-statistics
    { property-owner: tenant }
    { properties-managed: (get properties-managed tenant-stats), 
      active-tenancies: (+ (get active-tenancies tenant-stats) u1) }
  )
  
  (ok lease-id)))

;; Collect rent from security deposit
(define-public (collect-rent (lease-id uint))
  (match (map-get? property-leases { lease-id: lease-id })
    lease-data
    (let (
      (landlord (get landlord lease-data))
      (collectible-amount (calculate-collectible-rent lease-id))
      (current-collected (get rent-collected lease-data))
      (landlord-vault (get-vault-balance landlord))
    )
    (asserts! (is-eq tx-sender landlord) ERR_ACCESS_FORBIDDEN)
    (asserts! (get lease-valid lease-data) ERR_TENANCY_ENDED)
    (asserts! (> collectible-amount u0) ERR_INSUFFICIENT_SECURITY)
    
    ;; Update lease collected amount
    (map-set property-leases
      { lease-id: lease-id }
      (merge lease-data { rent-collected: (+ current-collected collectible-amount) })
    )
    
    ;; Add to landlord vault
    (map-set security-vaults
      { vault-owner: landlord }
      { vault-balance: (+ landlord-vault collectible-amount) }
    )
    
    (ok collectible-amount))
    ERR_LEASE_NOT_FOUND)
)

;; Pause rent collection (landlord only)
(define-public (pause-rent-collection (lease-id uint))
  (match (map-get? property-leases { lease-id: lease-id })
    lease-data
    (let (
      (landlord (get landlord lease-data))
      (current-timestamp (get-timestamp))
    )
    (asserts! (is-eq tx-sender landlord) ERR_ACCESS_FORBIDDEN)
    (asserts! (get lease-valid lease-data) ERR_TENANCY_ENDED)
    (asserts! (not (get rent-collection-paused lease-data)) ERR_RENT_FROZEN)
    
    (map-set property-leases
      { lease-id: lease-id }
      (merge lease-data { 
        rent-collection-paused: true,
        pause-timestamp: (some current-timestamp)
      })
    )
    
    (ok true))
    ERR_LEASE_NOT_FOUND)
)

;; Resume rent collection (landlord only)
(define-public (resume-rent-collection (lease-id uint))
  (match (map-get? property-leases { lease-id: lease-id })
    lease-data
    (let (
      (landlord (get landlord lease-data))
      (current-timestamp (get-timestamp))
      (pause-time (get pause-timestamp lease-data))
    )
    (asserts! (is-eq tx-sender landlord) ERR_ACCESS_FORBIDDEN)
    (asserts! (get lease-valid lease-data) ERR_TENANCY_ENDED)
    (asserts! (get rent-collection-paused lease-data) ERR_RENT_FROZEN)
    
    ;; Adjust commencement time for paused period
    (let (
      (paused-duration (match pause-time
        some-pause-time (- current-timestamp some-pause-time)
        u0))
      (new-commencement-time (+ (get lease-commencement lease-data) paused-duration))
      (new-expiration-time (match (get lease-expiration lease-data)
        some-expiration (some (+ some-expiration paused-duration))
        none))
    )
    
    (map-set property-leases
      { lease-id: lease-id }
      (merge lease-data { 
        rent-collection-paused: false,
        pause-timestamp: none,
        lease-commencement: new-commencement-time,
        lease-expiration: new-expiration-time
      })
    )
    
    (ok true)))
    ERR_LEASE_NOT_FOUND)
)

;; Terminate lease and settle deposits
(define-public (terminate-lease (lease-id uint))
  (match (map-get? property-leases { lease-id: lease-id })
    lease-data
    (let (
      (landlord (get landlord lease-data))
      (collectible-for-landlord (calculate-collectible-rent lease-id))
      (total-security (get security-deposit lease-data))
      (collected (get rent-collected lease-data))
      (return-amount (if (> (- total-security collected) collectible-for-landlord)
                       (- (- total-security collected) collectible-for-landlord)
                       u0))
      (landlord-vault (get-vault-balance landlord))
      (tenant-vault (get-vault-balance (get tenant lease-data)))
    )
    (asserts! (is-eq tx-sender landlord) ERR_ACCESS_FORBIDDEN)
    (asserts! (get lease-valid lease-data) ERR_TENANCY_ENDED)
    
    ;; Mark lease as terminated
    (map-set property-leases
      { lease-id: lease-id }
      (merge lease-data { lease-valid: false })
    )
    
    ;; Return remaining security deposit to tenant
    (if (> return-amount u0)
      (map-set security-vaults
        { vault-owner: (get tenant lease-data) }
        { vault-balance: (+ tenant-vault return-amount) })
      true)
    
    ;; Give final rent collection to landlord
    (if (> collectible-for-landlord u0)
      (begin
        (map-set security-vaults
          { vault-owner: landlord }
          { vault-balance: (+ landlord-vault collectible-for-landlord) })
        (map-set property-leases
          { lease-id: lease-id }
          (merge lease-data { 
            rent-collected: (+ collected collectible-for-landlord),
            lease-valid: false 
          })))
      true)
    
    (ok { returned-to-tenant: return-amount, final-rent-collection: collectible-for-landlord }))
    ERR_LEASE_NOT_FOUND)
)

;; Add additional security deposit
(define-public (add-security-deposit (lease-id uint) (additional-security uint))
  (match (map-get? property-leases { lease-id: lease-id })
    lease-data
    (let (
      (landlord (get landlord lease-data))
      (landlord-vault (get-vault-balance landlord))
      (current-security (get security-deposit lease-data))
    )
    (asserts! (is-eq tx-sender landlord) ERR_ACCESS_FORBIDDEN)
    (asserts! (get lease-valid lease-data) ERR_TENANCY_ENDED)
    (asserts! (>= landlord-vault additional-security) ERR_INSUFFICIENT_SECURITY)
    (asserts! (> additional-security u0) ERR_INVALID_TERMS)
    
    ;; Deduct from landlord vault
    (map-set security-vaults
      { vault-owner: landlord }
      { vault-balance: (- landlord-vault additional-security) }
    )
    
    ;; Update lease security deposit
    (map-set property-leases
      { lease-id: lease-id }
      (merge lease-data { security-deposit: (+ current-security additional-security) })
    )
    
    (ok (+ current-security additional-security)))
    ERR_LEASE_NOT_FOUND)
)

;; Get property statistics for user
(define-read-only (get-property-stats (property-owner principal))
  (default-to { properties-managed: u0, active-tenancies: u0 }
    (map-get? property-statistics { property-owner: property-owner }))
)

;; Get lease ID by landlord and property index
(define-read-only (get-landlord-property (landlord principal) (index uint))
  (map-get? landlord-property-portfolio { landlord: landlord, property-index: index })
)

;; Get lease ID by tenant and tenancy index
(define-read-only (get-tenant-rental (tenant principal) (index uint))
  (map-get? tenant-rental-history { tenant: tenant, tenancy-index: index })
)

;; Get total lease count
(define-read-only (get-total-leases)
  (var-get lease-counter)
)

;; Check if lease term has expired
(define-read-only (has-lease-expired (lease-id uint))
  (match (map-get? property-leases { lease-id: lease-id })
    lease-data
    (let (
      (current-timestamp (get-timestamp))
      (expiration-time (get lease-expiration lease-data))
    )
    (or 
      (not (get lease-valid lease-data))
      (match expiration-time
        some-expiration (>= current-timestamp some-expiration)
        false)
      (>= (get rent-collected lease-data) (get security-deposit lease-data))))
    false)
)