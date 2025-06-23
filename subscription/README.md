
# 🏠 RentalFlow - Property & Asset Streaming Payments Contract

RentalFlow is a decentralized Clarity smart contract that facilitates **real-time, continuous rental payments** for property and asset usage. It enables **streaming rent collection**, **secure deposit management**, and **automated lease lifecycles**, supporting landlords and tenants in a trust-minimized environment.

---

## 🔧 Key Features

* ⏱ **Streaming Rent Payments**: Calculates rent based on actual occupancy duration.
* 🔐 **Security Deposit Vault**: Funds are held securely and automatically settled on lease termination.
* 📄 **Lease Lifecycle Management**: Execute, pause, resume, and terminate leases programmatically.
* 📊 **Property Statistics & Portfolio Tracking**: Keep track of leases by landlords and tenants.
* 🧾 **Automated Rent Collection**: Supports smart computation of collectible rent from deposits.

---

## 📁 Contract Structure

### Maps

* `property-leases`: Core lease agreement data.
* `security-vaults`: Stores users’ deposit balances.
* `property-statistics`: Tracks how many properties and tenancies a user has.
* `landlord-property-portfolio`: Indexes properties per landlord.
* `tenant-rental-history`: Indexes lease history per tenant.

### Data Variables

* `lease-counter`: Global lease ID tracker.

### Error Constants

```clojure
ERR_ACCESS_FORBIDDEN        ;; Unauthorized caller
ERR_LEASE_NOT_FOUND         ;; Lease ID doesn't exist
ERR_INSUFFICIENT_SECURITY   ;; Not enough funds in vault
ERR_LEASE_ACTIVE            ;; Lease already exists
ERR_INVALID_TERMS           ;; Invalid lease parameters
ERR_TENANCY_ENDED           ;; Operation on ended lease
ERR_RENT_FROZEN             ;; Rent already paused
```

---

## 🚀 How It Works

### 1. Deposit Funds

```clojure
(deposit-security amount)
```

Landlords deposit funds into their vault to secure lease creation and rent buffering.

---

### 2. Execute Lease

```clojure
(execute-lease tenant rent-per-second security-amount lease-term)
```

Creates a new lease agreement. Locks the security amount from landlord's vault.

---

### 3. Rent Collection

```clojure
(collect-rent lease-id)
```

Landlord collects rent in real-time, deducted from the security deposit based on streaming occupancy.

---

### 4. Pause & Resume Rent

```clojure
(pause-rent-collection lease-id)
(resume-rent-collection lease-id)
```

Pause and resume rent flow. Resumes adjust the lease timing to account for the paused duration.

---

### 5. Terminate Lease

```clojure
(terminate-lease lease-id)
```

Ends a lease, settles rent owed, and refunds unused deposit to the tenant.

---

### 6. Add Security Deposit

```clojure
(add-security-deposit lease-id additional-security)
```

Allows landlords to increase the deposit coverage on a lease.

---

## 📖 Read-Only Queries

* `get-lease-agreement lease-id`
* `get-vault-balance principal`
* `get-property-stats principal`
* `calculate-collectible-rent lease-id`
* `get-landlord-property landlord index`
* `get-tenant-rental tenant index`
* `get-total-leases`
* `has-lease-expired lease-id`

---

## 📌 Deployment Guidelines

1. Make sure Clarity VM is available (e.g., on [Stacks blockchain](https://docs.stacks.co/)).
2. Fund the deploying address for initial deposits.
3. Deploy `RentalFlow.clar` using your preferred method (CLI, IDE, or Explorer).
4. Test interactions using mock lease scenarios.

---

## 📚 Example Use Case

A landlord starts a lease with a tenant that pays **₦1 per second** for a 30-day term and secures **₦2.5 million** as a deposit. RentalFlow automatically tracks:

* Real-time usage
* Rent collectible
* Security deposit status
* Lease expiration and refund process

---

## ✅ Benefits

* **Trustless Lease Automation**
* **Transparent Property Management**
* **Efficient Use of On-chain Deposits**
* **Enables Fractional, Real-Time Billing**

---

## 🔒 Security Considerations

* Ensure deposit balances are sufficient before lease execution.
* Use `pause-rent-collection` wisely to avoid unexpected charges.
* Vault integrity is preserved by explicit transfer logic and read-only verifications.
