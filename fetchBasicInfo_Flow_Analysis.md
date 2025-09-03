# fetchBasicInfo Flow Analysis - Complete Documentation

## Overview
This document provides a comprehensive analysis of the `fetchBasicInfo` method in the Paytm OE (Onboarding Engine) system, tracing the complete execution flow from HTTP request to database queries.

## Architecture Summary
The system follows a layered architecture:
1. **Controller Layer** - HTTP endpoint handling
2. **Service Layer** - Business logic orchestration  
3. **Helper Service Layer** - Utility operations
4. **DAO Layer** - Database access
5. **Entity Layer** - Data models

---

## Complete Flow Breakdown

### 1. HTTP Entry Point
**File:** `SolutionLeadController.java`  
**Method:** `fetchLeadBasicDetails()`  
**Lines:** 466-518  
**Endpoint:** `GET /panel/v1/solution/lead/fetchBasicInfo`

**Parameters:**
- `leadType` (Set<String>) - Types of leads to fetch (BUSINESS_LEAD, SOLUTION_LEAD, CHILD_LEAD, RESELLER_SUB_MERCHANT_LEAD)
- `fetchModificationFlows` (boolean) - Whether to fetch modification flows
- `fetchTotalLinkedLeadsCount` (boolean) - Whether to fetch linked leads count
- `solution` (String) - Solution type
- `flowType` (String) - Flow type (online/offline/corporate/onus)
- `onboardingDocumentType` (String) - Document type (PAN/TAN/GRAM_PANCHAYAT_ID)
- `onboardingDocumentValue` (String) - Document value
- `entityType` (String) - Entity type
- `leadId` (String) - Specific lead ID
- `parentLeadId` (String) - Parent lead ID
- `businessLeadId` (String) - Business lead ID
- `pageNo` (Integer) - Page number for pagination
- `pageRecords` (Integer) - Records per page
- `model` (String) - Business model (B2B/B2C)
- `subModel` (String) - Sub model (Standalone/Aggregator/Franchise)
- `pgMid` (String) - Payment Gateway MID
- `displayName` (String) - Display name

### 2. Concurrency Control (Redis Locking)
**Implementation:** Redis-based distributed locking  
**Lock Key Format:**
```
FETCH_LEAD_LOCK_PREFIX + "." + leadType + "." + onboardingDocValue + 
"." + entityType + "." + flowType + "." + leadId + 
"." + parentLeadId + "." + businessLeadId
```
**Timeout:** 20 minutes (60 * 20 seconds)  
**Purpose:** Prevent duplicate processing of same request

### 3. Service Layer Orchestration
**File:** `SolutionLeadHelperService.java`  
**Primary Methods:**
- `fetchBasicInfo()` (Lines 340-351) - Entry point with validation
- `validateFetchRequest()` (Lines 353-386) - Parameter validation
- `fetchLeadDetails()` (Lines 388-413) - Main processing logic

**Processing Paths:**
1. **Count Path:** `fetchTotalLinkedLeadsCount=true` → Count linked leads
2. **Modification Path:** `fetchModificationFlows=true` → Fetch modification flows  
3. **Details Path:** Default → Fetch basic lead details

### 4. Service Factory Pattern
**File:** `SolutionServiceFactoryImpl.java`  
**Method:** `fetchServiceForEnterpriseMerchant(String leadType)`  
**Purpose:** Route to appropriate implementation based on lead type

**Service Implementations:**
- `BusinessLeadDetailsServiceImpl` → `BusinessLeadDetailsImpl`
- `SolutionLeadDetailsServiceImpl` → `SolutionLeadDetailsImpl`  
- `ChildLeadDetailsServiceImpl` → `ChildLeadDetailsImpl`
- `ResellerSubMerchantLeadDetailsServiceImpl` → `ResellerSubMerchantLeadDetailsServiceImpl`

### 5. Business Logic Layer
**File:** `BusinessLeadDetailsImpl.java` (Focus on Business Lead processing)  
**Method:** `fetchBasicDetails()` (Lines 72-150)

**Key Processing Steps:**
1. **Parameter Validation** (Lines 82-90)
   - Validate model is mandatory
   - Validate subModel (except for ONUS flow)
   - Validate document type and value

2. **Document Type Routing** (Lines 92-97)
   - **PAN Path:** `oeEnterpriseHelperService.fetchLeads()`
   - **TAN/Gram Panchayat Path:** `oeEnterpriseHelperService.fetchLeadsForOnbDocType()`

3. **Business Logic Processing** (Lines 105-124)
   - Franchise UBM detection
   - Model/SubModel filtering
   - COCO merchant handling

### 6. Helper Service Layer
**File:** `OEEnterpriseHelperService.java`

**PAN Query Method:** (Lines 5649-5651)
```java
public List<UserBusinessMapping> fetchLeads(String pan, String flowType, SolutionType solutionType) throws EncryptionException {
    return ubmDao.fetchUBMBySolutionSolutionTypeLevel2AndStatusAndUbmaiKeyValue(
        solutionType, flowType, Status.IN_PROGRESS, 
        UBMAdditionalInfoKey.PAN.name(), OECryptoService.encrypt(pan));
}
```

**Other Document Type Method:** (Lines 5654-5656)
```java
public List<UserBusinessMapping> fetchLeadsForOnbDocType(String onboardingDocType, String onboardingDocValue, String flowType, SolutionType solutionType) throws EncryptionException {
    return ubmDao.fetchUBMBySolutionSolutionTypeLevel2AndStatusAndUbmaiKeys(
        solutionType, flowType, Status.IN_PROGRESS, 
        UBMAdditionalInfoKey.ONBOARDING_DOCUMENT_TYPE.name(), onboardingDocType, 
        UBMAdditionalInfoKey.ONBOARDING_DOCUMENT_VALUE.name(), OECryptoService.encrypt(onboardingDocValue));
}
```

### 7. DAO Interface Layer
**File:** `IUserBusinessMappingDao.java`

**Interface Methods:**
- Line 350: `fetchUBMBySolutionSolutionTypeLevel2AndStatusAndUbmaiKeyValue()`
- Line 352: `fetchUBMBySolutionSolutionTypeLevel2AndStatusAndUbmaiKeys()`
- Line 118: `fetchAllChildLeads(String leadId)`
- Line 368: `getB2CDodoLead(String pan, String model, String subModel)`

### 8. DAO Implementation Layer - **ACTUAL DATABASE QUERIES**
**File:** `UserBusinessMappingDaoImpl.java`

#### Primary Query 1 (PAN-based): Lines 1334-1342
```java
public List<UserBusinessMapping> fetchUBMBySolutionSolutionTypeLevel2AndStatusAndUbmaiKeyValue(
    SolutionType solutionType, String solutionTypeLevel2, Status status, String key, String value) {
    
    Query query = getSession().createQuery(
        "select ubm from UserBusinessMapping ubm, UserBusinessMappingAdditionalInfo ubmai " +
        "where ubm.id = ubmai.userBusinessMapping.id " +
        "and ubm.solutionType = :solutionType " +
        "and ubm.solutionTypeLevel2 = :solutionTypeLevel2 " +
        "and ubm.status = :status " +
        "and ubmai.key = :key " +
        "and ubmai.value = :value");
        
    query.setParameter("solutionType", solutionType);
    query.setParameter("solutionTypeLevel2", solutionTypeLevel2);
    query.setParameter("status", status);
    query.setParameter("key", key);
    query.setParameter("value", value);
    return (List<UserBusinessMapping>) query.list();
}
```

#### Primary Query 2 (TAN/Gram Panchayat): Lines 1345-1349
```java
public List<UserBusinessMapping> fetchUBMBySolutionSolutionTypeLevel2AndStatusAndUbmaiKeys(
    SolutionType solutionType, String solutionTypeLevel2, Status status, 
    String key1, String value1, String key2, String value2) {
    
    Query query = getSlaveSession().createQuery(
        "select ubm from UserBusinessMapping ubm " +
        "inner join ubm.userBusinessMappingAdditionalInfos ubmai1 with ubmai1.key = :key1 " +
        "inner join ubm.userBusinessMappingAdditionalInfos ubmai2 with ubmai2.key = :key2 " +
        "where ubm.solutionType = :solutionType " +
        "and ubm.solutionTypeLevel2 = :solutionTypeLevel2 " +
        "and ubm.status = :status " +
        "and ubmai1.value = :value1 " +
        "and ubmai2.value = :value2");
        
    // Parameters set...
    return (List<UserBusinessMapping>) query.list();
}
```

### 9. Database Schema
**Primary Tables:**
1. **`user_business_mapping`** (aliased as `ubm`)
   - Primary entity table storing business lead information
   - Key fields: `id`, `uuid`, `cust_id`, `solution_type`, `solution_type_level_2`, `status`, `entity_type`

2. **`user_business_mapping_additional_info`** (aliased as `ubmai`)
   - Key-value metadata table
   - Key fields: `user_business_mapping_id`, `key`, `value`
   - Common keys: `PAN`, `ONBOARDING_DOCUMENT_TYPE`, `ONBOARDING_DOCUMENT_VALUE`, `MODEL`, `SUB_MODEL`, `LEGAL_NAME`

3. **`workflow_status`**
   - Workflow state tracking
   - Key fields: `user_business_mapping_id`, `workflow_node_id`, `is_active`

4. **`workflow_node`**
   - Workflow definitions
   - Key fields: `id`, `sub_stage`, `stage`

### 10. Response Processing
**File:** `BusinessLeadDetailsImpl.java`

**Response Building Methods:**
- `populateAdditionalInfo()` (Lines 220-227) - Build additional info
- `populateOptions()` (Lines 241-246) - Determine available actions
- `checkCreateSolutionOption()` (Lines 248-268) - CREATE_SOLUTION eligibility
- `checkModifyOption()` (Lines 270-290) - MODIFY eligibility  
- `checkModifyMidOption()` (Lines 292-320) - MODIFY_MID eligibility

**Response Structure:**
```json
{
  "statusCode": 200,
  "businessLeads": [
    {
      "leadId": "uuid",
      "workflowStage": "current_substage",
      "prevWorkflowStage": "previous_substage",
      "pan": "encrypted_pan_value",
      "model": "B2B|B2C",
      "subModel": "Standalone|Aggregator|Franchise",
      "legalName": "business_name",
      "entityType": "entity_type",
      "additionalInfo": {
        "metaData": {},
        "options": ["CREATE_SOLUTION", "MODIFY", "MODIFY_MID"]
      }
    }
  ],
  "modificationFlows": [...],  // if fetchModificationFlows=true
  "linkedLeadsCount": 0        // if fetchTotalLinkedLeadsCount=true
}
```

---

## Performance Considerations

### 1. Database Optimizations
- **Read-only transactions:** `@Transactional(readOnly = true)`
- **Slave database:** Uses `getSlaveSession()` for read operations
- **Indexed queries:** Queries use indexed columns (solution_type, status, key)

### 2. Security
- **Data encryption:** PAN and sensitive data encrypted using `OECryptoService`
- **Parameter validation:** Multiple validation layers
- **Access control:** Panel access checks

### 3. Concurrency
- **Redis locking:** Prevents duplicate processing
- **Session management:** Proper Hibernate session handling
- **Connection pooling:** Database connection optimization

---

## Error Handling

### Common Error Scenarios
1. **Validation Errors (400):**
   - Missing mandatory parameters
   - Invalid parameter combinations
   - Business rule violations

2. **Duplicate Processing (400):**
   - Redis lock conflicts
   - Concurrent request handling

3. **Internal Errors (500):**
   - Database connection issues
   - Encryption/decryption failures
   - Unexpected exceptions

### Error Response Format
```json
{
  "statusCode": 400|500,
  "displayMessage": "Error description"
}
```

---

## Key Files and Line References

| Component | File | Key Methods | Lines |
|-----------|------|-------------|-------|
| Controller | SolutionLeadController.java | fetchLeadBasicDetails() | 466-518 |
| Service | SolutionLeadHelperService.java | fetchBasicInfo(), fetchLeadDetails() | 340-413 |
| Implementation | BusinessLeadDetailsImpl.java | fetchBasicDetails() | 72-150 |
| Helper | OEEnterpriseHelperService.java | fetchLeads(), fetchLeadsForOnbDocType() | 5649-5656 |
| DAO Interface | IUserBusinessMappingDao.java | Interface declarations | 350, 352 |
| DAO Implementation | UserBusinessMappingDaoImpl.java | **ACTUAL DATABASE QUERIES** | 1334-1349 |

---

## Conclusion

The `fetchBasicInfo` flow demonstrates a well-architected enterprise system with:
- **Proper separation of concerns** across multiple layers
- **Robust concurrency control** using Redis distributed locking
- **Comprehensive validation** at multiple levels
- **Security through encryption** of sensitive data
- **Performance optimization** through read-only transactions and slave database usage
- **Flexible response handling** based on request parameters

The actual database queries are executed in the `UserBusinessMappingDaoImpl.java` file at lines 1334-1349, using HQL (Hibernate Query Language) that gets translated to SQL for querying the `user_business_mapping` and `user_business_mapping_additional_info` tables.
