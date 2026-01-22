
;; title: Bitcoin-Yield-Optimization-Strategy
;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant PROTOCOL-VERSION u1)
(define-constant MAX-PLATFORMS u5)
(define-constant BASE-ALLOCATION-PERCENTAGE u20)

;; Access Control Roles
(define-constant ROLE-ADMIN u1)
(define-constant ROLE-MANAGER u2)
(define-constant ROLE-USER u3)

;; Error Codes
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-INSUFFICIENT-BALANCE (err u101))
(define-constant ERR-PLATFORM-LIMIT-REACHED (err u102))
(define-constant ERR-INVALID-ALLOCATION (err u103))
(define-constant ERR-EMERGENCY-LOCK (err u104))


;; State Variables
(define-data-var emergency-mode bool false)
(define-data-var total-locked-liquidity uint u0)
(define-data-var protocol-fee-percentage uint u2)

;; Platform Configuration
(define-map yield-platforms 
  { 
    platform-id: uint 
  }
  {
    name: (string-ascii 50),
    base-apy: uint,
    risk-score: uint,
    total-liquidity: uint,
    is-active: bool
  }
)

;; User Position Tracking
(define-map user-positions 
  { 
    user: principal 
  }
  {
    total-deposited: uint,
    current-yield: uint,
    last-deposit-time: uint,
    position-nft: uint
  }
)

;; Governance Tracking
(define-map governance-votes
  {
    proposal-id: uint,
    voter: principal
  }
  {
    voting-power: uint,
    vote-direction: bool
  }
)

;; Enhanced Deposit Function
(define-public (deposit-funds 
  (amount uint)
  (platform-id uint)
)
  (begin
    ;; Check emergency mode
    (asserts! (not (var-get emergency-mode)) ERR-EMERGENCY-LOCK)
    
    ;; Validate deposit
    (asserts! (> amount u0) ERR-INSUFFICIENT-BALANCE)
    
    ;; Transfer funds
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    ;; Update user position
    (map-set user-positions 
      { user: tx-sender }
      {
        total-deposited: amount,
        current-yield: u0,
        last-deposit-time: stacks-block-height,
        position-nft: u0
      }
    )
    
    ;; Update platform liquidity
    (let 
      ((current-platform (unwrap! 
        (map-get? yield-platforms { platform-id: platform-id }) 
        ERR-UNAUTHORIZED
      )))
      (map-set yield-platforms 
        { platform-id: platform-id }
        (merge current-platform 
          { 
            total-liquidity: (+ 
              (get total-liquidity current-platform) 
              amount 
            )
          }
        )
      )
    )
    
    ;; Emit deposit event
    (print { 
      event: "deposit", 
      user: tx-sender, 
      amount: amount,
      platform: platform-id 
    })
    
    (ok true)
  )
)

;; Advanced Withdrawal Mechanism
(define-public (withdraw-funds 
  (amount uint)
  (platform-id uint)
)
  (begin
    ;; Validate withdrawal
    (asserts! (not (var-get emergency-mode)) ERR-EMERGENCY-LOCK)
    
    (let 
      (
        (user-position (unwrap! 
          (map-get? user-positions { user: tx-sender }) 
          ERR-UNAUTHORIZED
        ))
        (current-platform (unwrap! 
          (map-get? yield-platforms { platform-id: platform-id }) 
          ERR-UNAUTHORIZED
        ))
        
        ;; Calculate withdrawal with fee
        (fee (/ (* amount (var-get protocol-fee-percentage)) u100))
        (net-withdrawal (- amount fee))
      )
      
      ;; Transfer funds back
      (try! (stx-transfer? 
        net-withdrawal 
        (as-contract tx-sender) 
        tx-sender
      ))
      
      ;; Update platform and user state
      (map-set yield-platforms 
        { platform-id: platform-id }
        (merge current-platform 
          { 
            total-liquidity: (- 
              (get total-liquidity current-platform) 
              amount 
            )
          }
        )
      )
      
      (map-set user-positions 
        { user: tx-sender }
        (merge user-position 
          { 
            total-deposited: (- 
              (get total-deposited user-position) 
              amount 
            )
          }
        )
      )
      
      (ok true)
    )
  )
)
