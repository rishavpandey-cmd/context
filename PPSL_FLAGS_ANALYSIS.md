# PPSL Database Flags Analysis

## Overview
This document analyzes all the flags, status indicators, and configuration columns found in the PPSL database tables. These flags control various aspects of the system including business logic, user access, payment processing, and workflow management.

## Core Business Logic Flags

### 1. User Business Mapping (`user_business_mapping`)
**Primary business entity table with key status flags:**

| Column | Type | Default | Purpose |
|--------|------|---------|---------|
| `status` | int | 0 | Main status flag for business mapping (0=inactive, 1=active, etc.) |
| `priority` | tinyint | 3 | Priority level for processing (1=highest, 5=lowest) |
| `entity_type` | enum | NULL | Business entity type (INDIVIDUAL, PRIVATE_LIMITED, etc.) |
| `ownership_type` | enum | NULL | Ownership type (APPLICANT, AGENT, AUTHORIZED_SIGNATORY) |

**Key Insights:**
- Status 0 likely means inactive/pending
- Priority system for queue management
- Entity type controls business rules and validation

### 2. Business Table (`business`)
**Core business entity with validation and compliance flags:**

| Column | Type | Default | Purpose |
|--------|------|---------|---------|
| `status` | int | 0 | Business status (0=inactive, 1=active) |
| `isPanNameMatchSuccess` | bit(1) | NULL | PAN name validation success flag |
| `is_fatca_declared` | bit(1) | NULL | FATCA compliance declaration |
| `is_pan_encrypted` | tinyint(1) | 0 | PAN encryption status |

**Key Insights:**
- PAN validation is critical for KYC compliance
- FATCA compliance tracking for international businesses
- Data encryption status for sensitive information

## Payment Gateway Configuration Flags

### 3. PG Solution Details (`pg_solution_details`)
**Payment gateway solution configuration with multiple boolean flags:**

| Column | Type | Default | Purpose |
|--------|------|---------|---------|
| `is_rule_optional` | int | 0 | Whether rules are optional for this solution |
| `is_default_fetch_with_rule` | int | 1 | Default behavior for rule fetching |
| `is_first_matched_rule_fetch` | int | 0 | Fetch first matching rule only |
| `persist_matched_rule_details` | int | 0 | Persist rule matching details |
| `enable_rule_sequencing` | int | 0 | Enable rule execution sequencing |
| `consult_risk_engine_limit_framework` | int | 0 | Risk engine integration flag |
| `is_mdr_override_config` | int | 1 | MDR (Merchant Discount Rate) override configuration |

**Key Insights:**
- Complex rule engine with multiple configuration options
- Risk engine integration for fraud prevention
- MDR override capability for pricing flexibility

### 4. PG Rule (`pg_rule`)
**Payment gateway rules with status and validation flags:**

| Column | Type | Default | Purpose |
|--------|------|---------|---------|
| `status` | int | NULL | Rule status (active/inactive) |
| `mandatory_params` | int | NULL | Number of mandatory parameters |
| `is_business_doc_provided` | int | 1 | Business document requirement flag |

**Key Insights:**
- Rules can be enabled/disabled via status
- Parameter validation requirements
- Document requirements for business validation

## Workflow Management Flags

### 5. Workflow Config (`workflow_config`)
**Workflow configuration with activation flags:**

| Column | Type | Default | Purpose |
|--------|------|---------|---------|
| `is_active` | tinyint(1) | NULL | Configuration activation status |

### 6. Workflow Status (`workflow_status`)
**Individual workflow instance status:**

| Column | Type | Default | Purpose |
|--------|------|---------|---------|
| `is_active` | tinyint(1) | NULL | Workflow instance active status |

**Key Insights:**
- Two-level workflow management (config + instance)
- Granular control over workflow execution

## Solution Configuration Flags

### 7. Solution Config (`solution_config`)
**Solution-specific configuration flags:**

| Column | Type | Default | Purpose |
|--------|------|---------|---------|
| `is_business_wallet_enabled` | int | 0 | Business wallet feature flag |

### 8. Solution (`solution`)
**Core solution entity with status:**

| Column | Type | Default | Purpose |
|--------|------|---------|---------|
| `status` | int | 0 | Solution status (0=inactive, 1=active) |

### 9. Solution Additional Info (`solution_additional_info`)
**Extended solution configuration:**

| Column | Type | Default | Purpose |
|--------|------|---------|---------|
| `status` | int | 0 | Additional info status |
| `is_sol_value_encrypted` | tinyint(1) | 0 | Value encryption flag |

## User Management Flags

### 10. Users (`users`)
**User account with extensive feature flags:**

| Column | Type | Default | Purpose |
|--------|------|---------|---------|
| `status` | tinyint | NULL | User account status |
| `show_tnc` | tinyint | 1 | Show terms and conditions |
| `create_wallet` | tinyint | 0 | Wallet creation flag |
| `logout_required` | tinyint | 0 | Force logout flag |
| `validate_otp_step` | tinyint | 1 | OTP validation requirement |
| `is_ekyc_enabled` | tinyint | 0 | eKYC feature flag |
| `location_service_enable` | tinyint | 0 | Location service flag |
| `default_camera_enable` | tinyint | 0 | Camera feature flag |
| `agent_present` | tinyint(1) | 1 | Agent presence flag |

**Key Insights:**
- Granular feature control per user
- Security and compliance flags (OTP, eKYC)
- UI/UX feature toggles

### 11. Roles (`roles`)
**Role-based access control:**

| Column | Type | Default | Purpose |
|--------|------|---------|---------|
| `status` | tinyint | NULL | Role status (active/inactive) |
| `source` | int | 1 | Role source (1=system, 2=user-defined) |

### 12. User Roles (`user_roles`)
**User-role mapping with status:**

| Column | Type | Default | Purpose |
|--------|------|---------|---------|
| `status` | tinyint | 1 | User-role mapping status |

## System Configuration Flags

### 13. Channels Config (`channels_config`)
**Channel-specific configuration:**

| Column | Type | Default | Purpose |
|--------|------|---------|---------|
| `status` | int | 1 | Channel status (1=active, 0=inactive) |

### 14. Circuit Breaker Config (`circuit_breaker_config`)
**Resilience and fault tolerance:**

| Column | Type | Default | Purpose |
|--------|------|---------|---------|
| `writable_stack_trace_enabled` | tinyint(1) | 0 | Stack trace logging flag |

## Flag Categories and Patterns

### Status Flags (Common Pattern)
- **0**: Inactive/Disabled/Pending
- **1**: Active/Enabled/Approved
- **NULL**: Not set/Unknown

### Boolean Flags (tinyint(1) or bit(1))
- **0**: False/Disabled
- **1**: True/Enabled
- **NULL**: Not configured

### Priority Flags
- **1**: Highest priority
- **3**: Default/Normal priority
- **5**: Lowest priority

## Business Logic Implications

### 1. **Multi-Level Status Management**
- Business → Solution → User → Role hierarchy
- Each level has independent status control
- Cascading effects when parent entities are disabled

### 2. **Feature Toggle Architecture**
- Granular control over features per user/solution
- A/B testing capability through flag management
- Gradual feature rollout support

### 3. **Compliance and Security**
- KYC/KYB validation flags
- FATCA compliance tracking
- Data encryption status
- OTP and eKYC requirements

### 4. **Payment Processing Control**
- Rule engine configuration
- Risk engine integration
- MDR override capabilities
- Transaction flow control

### 5. **Workflow Management**
- Config-level and instance-level control
- Dynamic workflow activation
- Process state management

## Recommendations

### 1. **Flag Documentation**
- Document all status code meanings
- Create flag reference guide
- Implement flag validation rules

### 2. **Monitoring and Alerting**
- Monitor flag changes in production
- Alert on critical flag modifications
- Track flag usage patterns

### 3. **Testing Strategy**
- Test all flag combinations
- Validate flag cascading effects
- Performance testing with different flag states

### 4. **Administration Interface**
- Create flag management UI
- Implement audit trail for flag changes
- Role-based flag modification permissions

---

*This analysis provides a comprehensive overview of all flags and configuration options in the PPSL system. These flags control critical business logic, security, compliance, and user experience aspects of the platform.*
