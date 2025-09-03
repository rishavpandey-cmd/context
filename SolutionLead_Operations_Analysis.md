# Solution Lead Operations Analysis - Complete Documentation

## Overview
This document provides a comprehensive analysis of solution lead operations in the Paytm OE (Onboarding Engine) system, covering creation, updation, and fetching of solution leads through various endpoints in the `SolutionLeadController.java`.

## Architecture Summary
The system follows a sophisticated multi-layered architecture with factory patterns for dynamic service resolution:
1. **Controller Layer** - HTTP endpoint handling for multiple operations
2. **Service Factory Layer** - Dynamic service resolution based on solution/entity type
3. **Business Logic Layer** - Entity-specific processing implementations
4. **DAO Layer** - Database access and transaction management
5. **Entity Layer** - Data models and workflow management

---

## Endpoint Analysis

### 1. Solution Lead Endpoints Overview

| Endpoint | Method | Purpose | Key Features |
|----------|--------|---------|--------------|
| `/lead` | POST | Create Solution Lead | Basic creation with validation |
| `/lead` | PUT | Update Solution Lead | Update with bank dedupe check |
| `/lead` | GET | Fetch Solution Lead Details | Retrieve lead information |
| `/createUpdateLead` | POST | Create/Update (Unified) | Redis locking, comprehensive validation |

---

## Detailed Flow Analysis

### 1. POST /lead - Create Solution Lead

**File:** `SolutionLeadController.java`  
**Method:** `createSolutionLead()`  
**Lines:** 111-143

#### Parameters:
- `entityType` (String, required) - Type of entity (INDIVIDUAL, PROPRIETORSHIP, etc.)
- `solution` (String, required) - Solution type identifier
- `channel` (String) - Channel identifier (defaults to OE_PANEL)
- `solutionDetails` (SolutionLeadRequest, body) - Complete lead details

#### Processing Flow:
1. **Validation Phase**
   - Binding result validation for request body
   - Error aggregation and response formatting

2. **Setup Phase**
   - Extract agent customer ID from thread context
   - Set default channel if not provided

3. **Service Resolution**
   ```java
   oeServiceFactory.getOESolutionServiceFromServiceFactory(
       SolutionType.valueOf(solution), 
       EntityType.valueOf(entityType),
       Channel.valueOf(channel)
   ).createSolutionLead(...)
   ```

4. **Error Handling**
   - `CreateOrUpdateLeadException` - Business logic errors
   - Generic exceptions with internal server error response

---

### 2. PUT /lead - Update Solution Lead

**File:** `SolutionLeadController.java`  
**Method:** `updateSolutionLead()`  
**Lines:** 146-195

#### Parameters:
- `entityType` (String) - Entity type
- `solution` (String) - Solution type
- `channel` (String) - Channel identifier
- `oeApplicationObjectSRO` (OEApplicationObjectSRO, body) - Update payload

#### Special Features:

**Bank Dedupe Check for Marketplace Solutions:**
```java
if (SolutionType.getMarketplaceSolutions().contains(SolutionType.valueOf(solution))
    && Objects.nonNull(oeApplicationObjectSRO.getBankDetails())
    && StringUtils.isNotBlank(oeApplicationObjectSRO.getBankDetails().getBankName())
    && StringUtils.isNotBlank(oeApplicationObjectSRO.getBankDetails().getBankAccountNumber())
    && StringUtils.isNotBlank(oeApplicationObjectSRO.getCustId())) {
    
    // Perform bank dedupe validation
    DuplicateBankResponseVO bankResponseVO = validateService.areBankDetailsDuplicateWithCustomMsg(
        Long.parseLong(oeApplicationObjectSRO.getCustId()),
        oeApplicationObjectSRO.getBankDetails().getBankName(),
        oeApplicationObjectSRO.getBankDetails().getBankAccountNumber()
    );
}
```

#### Processing Flow:
1. **Pre-validation**
   - Extract agent customer ID
   - Set default channel

2. **Conditional Bank Validation**
   - Check if solution is marketplace type
   - Validate bank details for duplicates
   - Create audit trail

3. **Service Resolution & Update**
   - Route to appropriate service implementation
   - Execute update operation

---

### 3. GET /lead - Fetch Solution Lead Details

**File:** `SolutionLeadController.java`  
**Method:** `fetchLeadDetails()`  
**Lines:** 212-247

#### Parameters:
- `leadType` (String, optional) - Type of lead to fetch
- `flowType` (String, optional) - Flow type identifier
- `pan` (String, optional) - PAN number
- `entityType` (String, optional) - Entity type
- `solution` (String, optional) - Solution type
- `channel` (String) - Channel identifier
- `parentLeadId` (String, optional) - Parent lead ID
- `businessLeadId` (String, optional) - Business lead ID
- `leadId` (String, optional) - Specific lead ID
- `solutionTypeLevel2` (String, optional) - Solution sub-type
- `modificationFlow` (String, optional) - Modification flow type
- `resellerId` (String, optional) - Reseller identifier
- `isCOCOMerchant` (boolean, optional) - COCO merchant flag
- `model` (String, optional) - Business model
- `subModel` (String, optional) - Business sub-model

#### Processing Flow:
1. **Setup**
   - Set default channel
   - Log request details

2. **Business Service Resolution**
   ```java
   oeServiceFactory.getOEBusinessService(
       SolutionType.valueOf(solution),
       EntityType.valueOf(entityType),
       Channel.valueOf(channel),
       solutionTypeLevel2
   ).fetchLeadDetails(...)
   ```

---

### 4. POST /createUpdateLead - Unified Create/Update

**File:** `SolutionLeadController.java**  
**Method:** `createUpdateSolutionLead()`  
**Lines:** 522-575

#### Advanced Features:
- **Redis Distributed Locking**
- **Comprehensive Validation Chain**
- **Unified Create/Update Logic**

#### Parameters:
- `entityType` (String, required) - Entity type
- `solution` (String, required) - Solution type
- `channel` (String) - Channel identifier
- `partialSave` (Boolean, optional) - Partial save flag
- `solutionTypeLevel2` (String, optional) - Solution sub-type
- `businessLeadId` (String, optional) - Business lead ID
- `solutionLeadId` (String, optional) - Solution lead ID
- `leadId` (String, optional) - Generic lead ID
- `modificationFlow` (String, optional) - Modification flow
- `solutionDetails` (SolutionLeadRequest, body) - Complete lead details

#### Redis Locking Strategy:
```java
String lockKey = MerchantConstants.CREATE_LEAD_LOCK_PREFIX + MerchantConstants.DOT + 
                entityType + MerchantConstants.DOT + solution + MerchantConstants.DOT + 
                businessLeadId + MerchantConstants.DOT + solutionLeadId + MerchantConstants.DOT + 
                onbDocValue;

boolean absentFlag = stringRedisTemplate.opsForValue().setIfAbsent(lockKey, "1");
stringRedisTemplate.expire(lockKey, 60 * 15, TimeUnit.SECONDS); // 15 minutes
```

#### Processing Flow:
1. **Concurrency Control**
   - Generate composite lock key
   - Attempt lock acquisition
   - Set 15-minute expiration

2. **Helper Service Delegation**
   ```java
   solutionLeadHelperService.createOrUpdateSolutionLead(
       solution, entityType, channel, agentCustId, partialSave,
       httpRequest, solutionDetails, businessLeadId, solutionLeadId,
       solutionTypeLevel2, leadId, modificationFlow
   );
   ```

3. **Cleanup**
   - Redis lock cleanup in finally block
   - Exception handling and logging

---

## Service Layer Deep Dive

### SolutionLeadHelperService Processing

**File:** `SolutionLeadHelperService.java`  
**Method:** `createOrUpdateSolutionLead()`  
**Lines:** 93-142

#### Processing Phases:

1. **Request Enhancement** (Lines 144-180)
   ```java
   updateDetailsInRequest(solutionDetails, solution, businessLeadId, 
                         solutionLeadId, solutionTypeLevel2, partialSave, 
                         leadId, modificationFlow);
   ```
   - Set solution type level 2
   - Handle parent-child lead relationships
   - Set MIT (Merchant Industry Type) for business leads
   - Populate UBM additional metadata

2. **Validation Chain**
   - `performRequestValidations()` - Basic field validation
   - `validatePanForSubModelFranchise()` - PAN validation for franchises
   - `validateEmailandMobileNumberForOnUsRequest()` - Contact validation
   - `performRequestValidationsWithExistingData()` - Data consistency check

3. **Existing Lead Check**
   ```java
   UserBusinessMapping ubm = solutionLeadHelperServiceImpl.fetchExistingEnterpriseLead(
       solution, solutionDetails, businessLeadId, solutionLeadId, modificationFlow
   );
   ```

4. **Decision Logic**
   ```java
   if(Objects.isNull(ubm)) {
       // CREATE PATH
       response = oeServiceFactory.getOESolutionServiceFromServiceFactory(...)
                 .createSolutionLead(...);
   } else {
       // UPDATE PATH
       response = oeServiceFactory.getOESolutionServiceFromServiceFactory(...)
                 .updateSolutionLead(...);
   }
   ```

---

## Service Factory Architecture

### OEServiceFactoryImpl Analysis

**File:** `OEServiceFactoryImpl.java`  
**Key Method:** `getOESolutionServiceFromServiceFactory()`  
**Lines:** 677-679

#### Service Resolution Process:
1. **Factory Method Call**
   ```java
   public OEAbstractSolutionLeadServiceImpl getOESolutionServiceFromServiceFactory(
       SolutionType solType, EntityType entityType, Channel channel) {
       return (OEAbstractSolutionLeadServiceImpl) getApplicableService(
           solType, entityType, channel, 
           ApplicationServiceType.SOLUTION_SERVICE, null, null
       );
   }
   ```

2. **Bean Resolution**
   ```java
   Object applicableBean = IApplicationFactoryBeanLoader.getApplicableBeanV2(
       solType, entityType, getChannel(solType, entityType, channel),
       applicationServiceType, solutionTypeLevel2, solutionTypeLevel3
   );
   ```

#### Service Implementations:

| Entity Type | Service Implementation | Purpose |
|-------------|----------------------|---------|
| INDIVIDUAL | OEIndividualApplicationServiceImpl | Individual merchant processing |
| PROPRIETORSHIP | OEProprietershipApplicationServiceImpl | Proprietorship business processing |
| PUBLIC_LTD/PRIVATE_LTD | OEPublicPrivateApplicationServiceImpl | Corporate entity processing |
| Enterprise Solutions | OEEnterpriseApplicationServiceImpl | Enterprise merchant processing |
| Mall Solutions | OEMallSolutionApplicationServiceImpl | Marketplace/mall processing |

---

## Database Operations

### UserBusinessMapping Entity Operations

#### Create Operations:
```sql
-- Main entity record
INSERT INTO user_business_mapping (
    uuid, cust_id, solution_type, solution_type_level_2,
    entity_type, status, created_at, updated_at, ...
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ...);

-- Additional metadata
INSERT INTO user_business_mapping_additional_info (
    user_business_mapping_id, key, value, created_at
) VALUES (?, ?, ?, ?);

-- Workflow initialization
INSERT INTO workflow_status (
    user_business_mapping_id, workflow_node_id, 
    is_active, created_at, ...
) VALUES (?, ?, ?, ?, ...);

-- Solution-specific data
INSERT INTO solution_additional_info (
    user_business_mapping_id, key, value, created_at
) VALUES (?, ?, ?, ?);
```

#### Update Operations:
```sql
-- Update main record
UPDATE user_business_mapping 
SET solution_type_level_2 = ?, status = ?, updated_at = ?
WHERE uuid = ?;

-- Update/Insert additional info
INSERT INTO user_business_mapping_additional_info (...)
VALUES (...)
ON DUPLICATE KEY UPDATE 
    value = VALUES(value), updated_at = VALUES(updated_at);

-- Workflow progression
UPDATE workflow_status 
SET is_active = 0 
WHERE user_business_mapping_id = ? AND is_active = 1;

INSERT INTO workflow_status (...)
VALUES (...);
```

#### Fetch Operations:
```sql
-- Fetch with additional info
SELECT ubm.*, ubmai.key, ubmai.value
FROM user_business_mapping ubm
LEFT JOIN user_business_mapping_additional_info ubmai 
    ON ubm.id = ubmai.user_business_mapping_id
WHERE ubm.uuid = ? AND ubm.status != 'REJECTED';

-- Fetch with workflow status
SELECT ubm.*, ws.*, wn.sub_stage
FROM user_business_mapping ubm
JOIN workflow_status ws ON ubm.id = ws.user_business_mapping_id
JOIN workflow_node wn ON ws.workflow_node_id = wn.id
WHERE ubm.uuid = ? AND ws.is_active = 1;
```

---

## Validation Framework

### 1. Request Validation Chain

#### Basic Field Validation:
- **Mandatory Fields:** Solution type, entity type validation
- **Regex Validation:** Email, mobile, PAN format validation
- **Business Rules:** Solution-entity compatibility

#### Category-Subcategory Validation:
```java
CategorySubCategoryRequest categorySubCategoryRequest = new CategorySubCategoryRequest();
categorySubCategoryRequest.setEntityType(entityType);
categorySubCategoryRequest.setSolutionName(solution);
categorySubCategoryRequest.setSolutionTypeLevel2(flowType);

CategorySubcategoryDTO category = fetchCatSubCatInfo(categorySubCategoryRequest, saiCategory);
CategorySubcategoryDTO subCategory = fetchCatSubCatInfo(categorySubCategoryRequest, saiSubCategory);
```

#### Bank Dedupe Validation:
```java
DuplicateBankResponseVO bankResponseVO = validateService.areBankDetailsDuplicateWithCustomMsg(
    custId, bankName, bankAccountNumber
);

if (!MerchantConstants.SUCCESS_STATUS_CODE.equals(bankResponseVO.getStatusCode())) {
    // Handle duplicate bank account error
    String dedupeErrorMsg = ErrorProcessingUtils.fetchBankDedupeErrorMsg(bankResponseVO);
    // Add error to solution additional info
}
```

### 2. Data Consistency Validation

#### Email/Mobile Validation for OnUs:
- Check for unique email/mobile combinations
- Validate against existing merchant records
- Handle OnUs flow special cases

#### PAN Validation for Franchise:
- Validate PAN for sub-model franchise cases
- Cross-check with existing business leads
- Handle enterprise fix flags

---

## Response Structure

### Success Response Format:
```json
{
  "statusCode": 200,
  "displayMessage": "Lead created/updated successfully",
  "leadId": "uuid-string",
  "workflowStage": "current_stage",
  "nextActions": ["DOCUMENT_UPLOAD", "VERIFICATION"],
  "additionalInfo": {
    "model": "B2B",
    "subModel": "AGGREGATOR",
    "flowType": "ONLINE"
  }
}
```

### Error Response Format:
```json
{
  "statusCode": 400,
  "displayMessage": "Validation error message",
  "errorDetails": {
    "field": "fieldName",
    "errorCode": "VALIDATION_ERROR",
    "errorMessage": "Detailed error description"
  }
}
```

### Fetch Response Format:
```json
{
  "statusCode": 200,
  "leadDetails": {
    "leadId": "uuid-string",
    "entityType": "PROPRIETORSHIP",
    "solutionType": "payment_gateway",
    "currentStage": "DOCUMENT_UPLOADED",
    "previousStage": "LEAD_CREATED",
    "businessDetails": {
      "legalName": "Business Name",
      "pan": "ABCDE1234F",
      "model": "B2C",
      "subModel": "STANDALONE"
    },
    "contactDetails": {
      "email": "business@example.com",
      "mobile": "+919876543210"
    },
    "documents": [...],
    "availableActions": ["VERIFY", "MODIFY"]
  }
}
```

---

## Error Handling Strategy

### Exception Hierarchy:
1. **ValidationException** - Request validation failures
2. **CreateOrUpdateLeadException** - Business logic errors
3. **EncryptionException** - Data encryption/decryption errors
4. **Generic Exception** - Unexpected system errors

### Error Response Mapping:
| Exception Type | HTTP Status | Error Handling |
|----------------|-------------|----------------|
| ValidationException | 400 BAD_REQUEST | Field validation errors |
| CreateOrUpdateLeadException | Custom (from exception) | Business rule violations |
| Bank Dedupe Failure | 417 EXPECTATION_FAILED | Duplicate bank account |
| Generic Exception | 500 INTERNAL_SERVER_ERROR | System errors |

---

## Performance Considerations

### 1. Concurrency Control
- **Redis Distributed Locking** - Prevents concurrent modifications
- **Lock Timeout Management** - 15-minute expiration for create/update
- **Lock Cleanup** - Guaranteed cleanup in finally blocks

### 2. Database Optimizations
- **Batch Operations** - Multiple inserts in single transaction
- **Indexed Queries** - Optimized lookup by UUID, status, solution type
- **Connection Pooling** - Hibernate session management

### 3. Caching Strategy
- **Service Bean Caching** - Factory pattern with bean caching
- **Configuration Caching** - Startup cache for business rules
- **Session Management** - Stateless service design

---

## Security Measures

### 1. Data Protection
- **Encryption** - PAN and sensitive data encryption using OECryptoService
- **Audit Trail** - Complete audit logging for all operations
- **Access Control** - Panel access checks and user validation

### 2. Validation Security
- **Input Sanitization** - Request body validation and sanitization
- **Business Rule Enforcement** - Multi-layer validation framework
- **Duplicate Prevention** - Bank dedupe and email/mobile uniqueness

---

## Monitoring and Logging

### 1. Audit Trail
```java
GenericAuditSRO genericAuditSRO = CurrentGenericAudit.getCurrentGenericAudit();
genericAuditSRO.setCustId(custId);
genericAuditSRO.setLeadId(leadId);
genericAuditSRO.setSolutionType(solution);
genericAuditSRO.setChannel(channel);
genericAuditSRO.setOeApi(requestURI);
```

### 2. Logging Strategy
- **Request/Response Logging** - Complete API interaction logging
- **Error Logging** - Detailed exception logging with stack traces
- **Performance Logging** - Service execution time tracking
- **Business Event Logging** - Lead state changes and transitions

---

## Configuration Management

### 1. Feature Flags
```java
// Enterprise fix flags
if(CommonUtils.isEnterpriseOnbFlagEnabled(OEConstants.ENTERPRISE_FIX_FLAG_6)) {
    // PAN validation for sub-model franchise
}

if(CommonUtils.isEnterpriseOnbFlagEnabled(OEConstants.ONLINE_FLOW_DISABLED)) {
    // Block online flow processing
}
```

### 2. Solution Type Configuration
- **Dynamic Service Mapping** - Configuration-driven service resolution
- **Channel Configuration** - Channel-specific processing rules
- **Validation Configuration** - Configurable validation rules

---

## Key Files and References

| Component | File | Key Methods | Lines |
|-----------|------|-------------|-------|
| Controller | SolutionLeadController.java | createSolutionLead(), updateSolutionLead(), fetchLeadDetails(), createUpdateSolutionLead() | 111-575 |
| Helper Service | SolutionLeadHelperService.java | createOrUpdateSolutionLead(), updateDetailsInRequest() | 93-180 |
| Service Factory | OEServiceFactoryImpl.java | getOESolutionServiceFromServiceFactory(), getApplicableService() | 677-719 |
| Validation | SolutionLeadHelperService.java | performRequestValidations(), validateCatSubCat() | 237-310 |
| DAO Layer | UserBusinessMappingDao | Insert/Update/Select operations | Various |

---

## Conclusion

The Solution Lead operations in the Paytm OE system demonstrate a sophisticated enterprise architecture with:

- **Multi-endpoint Support** - Different endpoints for different use cases
- **Dynamic Service Resolution** - Factory pattern for flexible service routing
- **Comprehensive Validation** - Multi-layer validation framework
- **Robust Concurrency Control** - Redis-based distributed locking
- **Extensive Error Handling** - Comprehensive exception management
- **Performance Optimization** - Caching, connection pooling, and optimized queries
- **Security Measures** - Data encryption, audit trails, and access control
- **Monitoring Capabilities** - Complete logging and audit framework

This architecture provides a scalable, maintainable, and robust foundation for solution lead management in an enterprise payment processing environment.
