# Technical Requirement & Architecture Document (TRAD)

## Next-Gen Vehicle & Identity Intelligence Platform

---

## 1\. System Architecture Overview

The system uses a clean, modern, decoupled microservices architecture designed for ultra-low latency, upstream fault tolerance, and financial-grade ledger integrity.

graph TD

    Client\[Mobile Apps: Android / iOS / Web Portal\] \--\> CDN\[Cloudflare API Shield / WAF\]

    CDN \--\> Gateway\[Kong API Gateway / Reverse Proxy\]

    Gateway \--\> AuthSvc\[Authentication & Session Service\]

    Gateway \--\> WalletSvc\[Wallet & Billing Engine\]

    Gateway \--\> VerificationSvc\[Verification Orchestration Service\]

    

    VerificationSvc \--\> Cache\[(Redis Distributed Cache)\]

    VerificationSvc \--\> DB\[(PostgreSQL Master-Replica)\]

    VerificationSvc \--\> UpstreamRouter\[Upstream Smart Provider Router\]

    

    UpstreamRouter \--\> P1\[Provider 1: Surepass / Karza / Signzy\]

    UpstreamRouter \--\> P2\[Provider 2: Sandbox.co.in / IDfy\]

    UpstreamRouter \--\> P3\[Government Fallback Bridge\]

    WalletSvc \--\> PG\[Payment Gateway: Cashfree / Razorpay / PayU\]

    WalletSvc \--\> DB

---

## 2\. Technology Stack

| Layer | Selected Tech | Rationale |
| :---- | :---- | :---- |
| **Mobile Client** | Flutter / Kotlin Multiplatform (or Native Kotlin \+ Jetpack Compose) | High performance, native hardware camera access for OCR, secure keystore storage. |
| **API Gateway** | Kong Gateway / Traefik | Rate limiting, JWT verification, HMAC request signature verification, DDoS mitigation. |
| **Backend Services** | Go (Golang) / Node.js (NestJS / TypeScript) | High concurrency for I/O heavy external API proxying, predictable memory footprint. |
| **Database** | PostgreSQL 16 (Amazon RDS / Supabase) | ACID compliance for double-entry financial wallet ledger, JSONB support for varied schema responses. |
| **Cache & Queue** | Redis 7 \+ Redis Streams / RabbitMQ | Sub-millisecond lookup for cached searches; background queue for async PDF generation and push notifications. |
| **Storage & Reports** | AWS S3 / Cloudflare R2 \+ Gotenberg / Chromium | Secure object storage with pre-signed short-lived URLs for generated inspection reports. |
| **Monitoring** | Prometheus, Grafana, OpenTelemetry, Sentry | Real-time tracing of upstream provider latency, error rates, and wallet transaction success rates. |

---

## 3\. High-Level Data Model (PostgreSQL)

### 3.1 Users Table (`users`)

CREATE TABLE users (

    id UUID PRIMARY KEY DEFAULT gen\_random\_uuid(),

    full\_name VARCHAR(120) NOT NULL,

    email VARCHAR(255) UNIQUE NOT NULL,

    mobile VARCHAR(15) UNIQUE NOT NULL,

    password\_hash VARCHAR(255) NOT NULL,

    role VARCHAR(20) DEFAULT 'user', \-- 'user', 'dealer', 'enterprise', 'admin'

    is\_active BOOLEAN DEFAULT TRUE,

    created\_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT\_TIMESTAMP,

    updated\_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT\_TIMESTAMP

);

### 3.2 Wallet Table (`wallets`)

CREATE TABLE wallets (

    id UUID PRIMARY KEY DEFAULT gen\_random\_uuid(),

    user\_id UUID UNIQUE REFERENCES users(id) ON DELETE CASCADE,

    balance NUMERIC(12, 2\) NOT NULL DEFAULT 0.00 CHECK (balance \>= 0.00),

    currency VARCHAR(3) DEFAULT 'INR',

    locked\_balance NUMERIC(12, 2\) NOT NULL DEFAULT 0.00,

    version BIGINT NOT NULL DEFAULT 0, \-- Optimistic concurrency control

    updated\_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT\_TIMESTAMP

);

### 3.3 Financial Ledger (`wallet_ledger`)

*Double-entry bookkeeping model to guarantee auditability and zero phantom debits.*

CREATE TABLE wallet\_ledger (

    id UUID PRIMARY KEY DEFAULT gen\_random\_uuid(),

    wallet\_id UUID REFERENCES wallets(id) ON DELETE RESTRICT,

    transaction\_type VARCHAR(10) NOT NULL, \-- 'CREDIT' or 'DEBIT'

    amount NUMERIC(12, 2\) NOT NULL,

    balance\_before NUMERIC(12, 2\) NOT NULL,

    balance\_after NUMERIC(12, 2\) NOT NULL,

    reference\_id VARCHAR(100), \-- Payment Gateway TXN ID or Query Request ID

    category VARCHAR(50) NOT NULL, \-- 'TOPUP', 'RC\_SEARCH', 'DL\_SEARCH', 'REFUND'

    description TEXT,

    created\_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT\_TIMESTAMP

);

### 3.4 Verification Queries Table (`verification_queries`)

CREATE TABLE verification\_queries (

    id UUID PRIMARY KEY DEFAULT gen\_random\_uuid(),

    user\_id UUID REFERENCES users(id) ON DELETE CASCADE,

    service\_type VARCHAR(40) NOT NULL, \-- 'RC\_SEARCH', 'CHASSIS\_SEARCH', 'DL', 'PAN', 'IRDAI'

    query\_identifier VARCHAR(50) NOT NULL, \-- vehicle number / DL / PAN

    cost\_deducted NUMERIC(8, 2\) NOT NULL DEFAULT 0.00,

    upstream\_provider VARCHAR(50),

    upstream\_status VARCHAR(20), \-- 'SUCCESS', 'FAILED', 'TIMEOUT'

    response\_payload JSONB,

    pdf\_report\_url VARCHAR(500),

    is\_cached BOOLEAN DEFAULT FALSE,

    created\_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT\_TIMESTAMP

);

CREATE INDEX idx\_user\_queries ON verification\_queries(user\_id, service\_type, created\_at DESC);

CREATE INDEX idx\_query\_identifier ON verification\_queries(service\_type, query\_identifier);

---

## 4\. API Endpoints Specification

### 4.1 Authentication & Profile

* `POST /api/v1/auth/register` \- Create account (validates OTP on mobile).  
* `POST /api/v1/auth/login` \- Authenticate via password or phone OTP; returns JWT \+ Refresh Token.  
* `POST /api/v1/auth/refresh-token` \- Exchange valid refresh token for access token.  
* `GET  /api/v1/user/profile` \- Fetch user details, role, and current wallet balance.

### 4.2 Wallet & Transactions

* `GET  /api/v1/wallet/balance` \- Live balance lookup.  
* `POST /api/v1/wallet/create-order` \- Initiates payment gateway transaction (Razorpay / Cashfree / PayU). Returns payment token.  
* `POST /api/v1/wallet/verify-webhook` \- Idempotent server-to-server webhook endpoint verifying payment signature and crediting wallet.  
* `GET  /api/v1/wallet/transactions` \- Paginated ledger history with date filters.

### 4.3 Verification Services

All verification requests require headers: `Authorization: Bearer <jwt>`, `X-Request-Id: <uuid>`, and payload HMAC signing `X-Signature`.

* `POST /api/v1/verify/rc` \- Fetch vehicle RC specs (body: `{ "registration_number": "MH12AB1234" }`).  
* `POST /api/v1/verify/chassis` \- Fetch vehicle specs by Chassis/VIN (body: `{ "chassis_number": "MA3..." }`).  
* `POST /api/v1/verify/owner-history` \- Fetch previous transfer details.  
* `POST /api/v1/verify/insurance` \- Fetch policy and insurer details.  
* `POST /api/v1/verify/driving-license` \- Fetch DL information (body: `{ "license_number": "DL...", "dob": "YYYY-MM-DD" }`).  
* `POST /api/v1/verify/pan` \- Fetch PAN validation and Aadhaar linkage (body: `{ "pan_number": "ABCDE1234F" }`).  
* `POST /api/v1/verify/pan-by-mobile` \- Find PANs linked to phone (body: `{ "mobile": "98...", "name": "..." }`).  
* `POST /api/v1/verify/irdai-agent` \- Validate IRDAI license (body: `{ "agent_id": "..." }`).

### 4.4 History & PDF Exports

* `GET  /api/v1/records/history?service=<type>&page=1&limit=20` \- Return past searches.  
* `GET  /api/v1/records/saved/:id` \- Return full saved payload without deducting balance.  
* `POST /api/v1/records/:id/generate-pdf` \- Asynchronously compiles branded PDF and returns signed download URL.

---

## 5\. Resilient Upstream Integration & Provider Fallback

Third-party KYC and verification vendors (Karza, Surepass, IDfy, Sandbox) occasionally suffer from downstream government downtime. The system implements a **Circuit Breaker & Fallback Router**:

sequenceDiagram

    autonumber

    Client \-\>\> Gateway: POST /api/v1/verify/rc

    Gateway \-\>\> VerificationSvc: Process Verification Request

    VerificationSvc \-\>\> Cache: Check Redis (TTL 48 Hours)

    alt Cache Hit

        Cache \--\>\> VerificationSvc: Return Cached Object

        VerificationSvc \--\>\> Client: 200 OK (Zero Charge or Discounted)

    else Cache Miss

        VerificationSvc \-\>\> WalletSvc: Check & Reserve Balance (Atomic)

        alt Insufficient Balance

            WalletSvc \--\>\> Client: 402 Payment Required

        else Balance Available

            VerificationSvc \-\>\> UpstreamRouter: Dispatch Query

            UpstreamRouter \-\>\> P1: Request Provider A

            alt Provider A Timeout / 503

                UpstreamRouter \-\>\> P2: Automatic Fallback to Provider B

            end

            P2 \--\>\> UpstreamRouter: 200 Valid Result

            UpstreamRouter \--\>\> VerificationSvc: Standardized Normalized Payload

            VerificationSvc \-\>\> DB: Save Query & Commit Wallet Debit

            VerificationSvc \-\>\> Cache: Store in Redis

            VerificationSvc \--\>\> Client: 200 OK Response

        end

    end

---

## 6\. Security & Infrastructure Architecture

1. **Optimistic Locking for Wallet Concurrency:**  
   * Prevents race conditions and double-spending across concurrent requests using version column (`UPDATE wallets SET balance = balance - 10, version = version + 1 WHERE id = :id AND version = :current_version`).  
2. **Payload Cryptography:**  
   * Critical verification queries implement HMAC-SHA256 signature checks preventing client-side man-in-the-middle request body manipulation.  
3. **Data Protection & Masking:**  
   * Sensitive PII (such as PAN, Aadhaar link status, and full engine/chassis numbers) is masked in logs and stored using AES-256 field-level encryption.  
4. **CI/CD & Container Orchestration:**  
   * Dockerized microservices deployed on Kubernetes (EKS / GKE) or serverless container apps with automated blue-green deployments and horizontal pod autoscaling based on CPU/Request queue depth.