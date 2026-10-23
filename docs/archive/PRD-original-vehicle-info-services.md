# Product Requirement Document (PRD)

## Next-Gen Vehicle & Identity Intelligence Platform ("AutoIntel AI")

---

## 1\. Executive Summary

**AutoIntel AI** is a comprehensive, mobile-first B2B/B2C vehicle verification, identity intelligence, and compliance inspection platform. Inspired by utility tools like Vehicle AI Services, AutoIntel empowers used-car dealerships, insurance aggregators, auto financiers, fleet operators, mechanics, and individual vehicle buyers to perform real-time verification of vehicle registration (RC), ownership transfer histories, insurance coverage, driving licenses, PAN records, and IRDAI agent credentials.

The platform eliminates fraud in used-car sales, speeds up insurance underwriting, and simplifies customer due diligence through prepaid micro-transactions and enterprise subscription tiers.

---

## 2\. Market Problem & Opportunity

* **High Incidence of Used-Car Fraud:** Hidden hypothecation (loans), fake ownership identities, tampered chassis numbers, and lapsed insurance policies make second-hand car buying risky.  
* **Fragmented Verification Silos:** Parivahan/Vahan (RC/DL), NSDL/ITD (PAN), IIB (Insurance Information Bureau), and IRDAI portals are disconnected and slow for field agents.  
* **Slow Underwriting & Onboarding:** Auto-dealers and independent brokers lack a unified mobile utility where they can query records on the go with zero friction and instant exportable PDF reports.

---

## 3\. User Personas

### Persona A: Used-Car Dealer / Broker ("Rajesh")

* **Goal:** Verify vehicle ownership history, active hypothecation (financer), chassis-to-engine matching, and past fitness before purchasing or listing inventory.  
* **Pain Point:** Cannot risk buying a vehicle with disputed ownership or forged papers. Needs quick mobile checks while standing at a customer's location.

### Persona B: Insurance Agent / Surveyor ("Pooja")

* **Goal:** Verify policy active dates, insurer validity, IRDAI agency certificates, and driver license authenticity during claim assessment or policy renewal.  
* **Pain Point:** Needs downloadable, watermarked PDF audit trails with verified timestamps.

### Persona C: Fleet Manager & Logistics Operator ("Amit")

* **Goal:** Batch track commercial vehicle fitness, pollution check (PUCC) expiry, road tax validity, and driver license legitimacy.  
* **Pain Point:** Penalties from challans due to unnoticed document expirations.

### Persona D: Individual Car/Bike Buyer ("Sneha")

* **Goal:** One-off vehicle check before transferring token money for a used vehicle on platforms like OLX or Spinny.  
* **Pain Point:** Reluctant to buy expensive subscriptions; prefers simple per-search UPI micropayments.

---

## 4\. Product Features & Functional Requirements

### 4.1 Core Verification Services

1. **Vehicle RC Intelligence (Search by Vehicle / Registration Number):**  
   * Inputs: Registration Number (e.g., `MH12AB1234`).  
   * Output: Owner Name, Maker/Model, Vehicle Class, Fuel Type, Registration Date, Registering Authority (RTO), Hypothecation/Financier details, Fitness validity, Tax validity, PUCC expiry, Engine & Chassis number (masked/unmasked based on tier).  
2. **Vehicle Lookup by Chassis / VIN Number:**  
   * Query records directly using 17-character VIN when plate number is absent or tampered.  
3. **Vehicle Ownership Sequence & Transfer History:**  
   * Chronological breakdown of 1st owner, 2nd owner, transfer dates, and ownership change events.  
4. **Vehicle Insurance Status & Coverage Query:**  
   * Policy status (Active/Expired), Insurance Company, Policy Number, Expiry Date, Zero Dep / Third-party classification.  
5. **Registered Mobile Number Lookup by RC:**  
   * Fetch masked or linked phone records associated with the vehicle for communication/recovery.  
6. **Driving License (DL) Live Verification:**  
   * Inputs: DL Number \+ Date of Birth.  
   * Output: Driver Name, Validity (Transport vs. Non-Transport), Badge details, Vehicle classes permitted.  
7. **PAN Card Verification & Aadhaar Seeding Status:**  
   * Inputs: PAN Number.  
   * Output: Registered Full Name, PAN category (Individual/Company), Aadhaar link status (`Linked`/`Not Linked`).  
8. **PAN Discovery by Mobile:**  
   * Inputs: Mobile Number \+ Full Name.  
   * Output: Linked PAN details.  
9. **IRDAI Agent Certification Verification:**  
   * Inputs: Agent Code / License Number.  
   * Output: Agent Name, Insurer Agency, Appointment Date, License Validity status.

### 4.2 Utility & Workflow Features

* **PDF Report Generation:** Instant generation of branded, tamper-evident inspection reports with verification timestamp, summary pills, and QR codes for digital verification.  
* **Offline / Cached History Storage:** Saved queries are accessible forever without re-charging wallet balance.  
* **Push Notifications & Expiry Alerts:** Alerts for RC Fitness, PUCC, and Insurance expiration.  
* **Multi-Language Support:** Regional language support (English, Hindi, Bengali, Tamil, Telugu, Kannada, Gujarati, Marathi) catering to regional brokers.  
* **Direct Helpdesk / WhatsApp Concierge:** Instant one-tap support via WhatsApp chat integration.

---

## 5\. Non-Functional Requirements (NFR)

* **Response Latency:** Primary API searches must return in `< 2.5 seconds` on 4G/5G networks. Cached/saved records in `< 300ms`.  
* **Availability:** 99.9% uptime for core mobile app and wallet APIs.  
* **Scalability:** Capable of handling peak burst of 200 queries/sec with upstream queueing and automatic failover.  
* **Cross-Platform Compatibility:** Native Android (Kotlin / Jetpack Compose) and iOS (Swift / SwiftUI) with parity.  
* **Security & Privacy:** Compliance with Digital Personal Data Protection Act (DPDPA 2023). End-to-end HTTPS with TLS 1.3, payload signing, and data masking.

---

## 6\. Success Metrics & KPIs

* **Daily Active Users (DAU) & Monthly Active Users (MAU).**  
* **Query Success Rate:** \> 97% valid responses without upstream timeouts.  
* **Wallet Recharge Conversion Rate:** \> 25% of registered users recharging within 7 days.  
* **Cost Per Verification (CPV):** Maintained below 40% of retail price charged.  
* **Report Share Rate:** \> 30% of searches exported to PDF or shared via WhatsApp.

---

## 7\. Product Release Roadmap

### Phase 1: MVP (Week 1\)

* Core RC, DL, Insurance, and PAN verification APIs.  
* Prepaid Wallet with UPI/Payment Gateway integration.  
* Number plate OCR scanner via camera.  
* PDF report export and search history.  
* English \+ Hindi support.

### Phase 2: Growth & Retention (Week 2-3)

* Chassis lookup, ownership timeline history, and IRDAI agent checks.  
* Expiry alerts & Document Locker (store user's personal RC/DL).  
* 6 Regional languages added.

### Phase 3: Advanced AI & Monetization (Week 2-3)

* Used-car valuation engine (predictive price based on age, fuel, and owner count).  
* API B2B access for dealerships with webhooks.  
* Enterprise Web Dashboard for bulk searches.