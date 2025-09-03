# Fetch Merchant Banks Operations Analysis - `fetchMerchantBanks` Endpoint

## 📋 **Overview**
The `fetchMerchantBanks` endpoint in `SolutionLeadController.java` handles retrieval of suggested bank accounts for merchants based on their lead information, with support for UPI-only fetching and bank account linking status checks.

## 🔗 **Endpoint Details**
- **URL:** `GET fetchMerchantBanks`
- **Controller Method:** `fetchMerchantBanks` (lines 630-650)
- **Primary Service:** `IMerchantBankDetailsService.fetchSuggestedBanks`
- **Request Parameters:** `leadId`, `merchantCustId`, `upiFetchOnly`, `trackingRefId`
- **Response:** `MerchantBankDetailsResponse`

## 🏗️ **Complete Technical Flow**

### **1. Controller Layer** (`SolutionLeadController.java`)

```java
@RequestMapping(value = "fetchMerchantBanks", method = RequestMethod.GET)
public ResponseEntity fetchMerchantBanks(@Context HttpServletRequest httpRequest, 
                                        @Context HttpServletResponse httpResponse, 
                                        @RequestParam String leadId,
                                        @RequestParam(required = false) String merchantCustId, 
                                        @RequestParam boolean upiFetchOnly, 
                                        @RequestParam(required = false) String trackingRefId) {
    try {
        // Delegate to merchant bank details service
        MerchantBankDetailsResponse response = merchantBankDetailsService.fetchSuggestedBanks(
            leadId, merchantCustId, upiFetchOnly, trackingRefId);
        
        // Set success response
        response.setStatusCode(HttpStatus.OK.value());
        response.setSuccessMsg(OEConstants.success);
        return ResponseEntity.status(HttpStatus.OK.value()).body(response);
        
    } catch (BadRequestException e) {
        LOGGER.info("Bad request, error desc:" + e.getStatusMessage());
        BaseResponse response = OEErrorProcessingUtils.handleResponse(
            new BaseResponse(), 
            HttpStatus.BAD_REQUEST.value(),
            e.getMessage());
        return ResponseEntity.status(response.getStatusCode()).body(response);
        
    } catch (Exception e) {
        LOGGER.error("Error while fetching UPI banks", e);
        BaseResponse response = OEErrorProcessingUtils.handleResponse(
            new BaseResponse(), 
            HttpStatus.INTERNAL_SERVER_ERROR.value(),
            MerchantConstants.INTERNAL_SERVER_ERROR_MSG);
        return ResponseEntity.status(response.getStatusCode()).body(response);
    }
}
```

**Key Parameters:**
- **leadId**: Lead identifier (required)
- **merchantCustId**: Merchant customer ID (optional)
- **upiFetchOnly**: Boolean flag for UPI-only operations
- **trackingRefId**: Tracking reference ID for UPI operations (optional)

### **2. Service Layer** (`MerchantBankDetailsServiceImpl.java`)

#### **Main Processing Flow:**

**Step 1: Input Validation and Lead Retrieval**
```java
@Override
public MerchantBankDetailsResponse fetchSuggestedBanks(String leadId, String merchantCustId, 
                                                      boolean upiFetchOnly, String trackingId) 
                                                      throws Exception {
    LOGGER.info("fetch merchant bank request : " + "merchatCUstId : " + merchantCustId + 
                " trackingId : " + trackingId + " upiOnlyFlag : " + upiFetchOnly);

    MerchantBankDetailsResponse merchantBankDetailsResponse = new MerchantBankDetailsResponse();
    
    // Fetch lead by ID
    UserBusinessMapping ubm = ubmDao.getLeadByLeadId(leadId);
    if (Objects.isNull(ubm))
        throw new BadRequestException(ErrorMessages.INVALID_LEAD_ID);
    
    // Get appropriate service factory implementation
    OEAbstractApplicationService oeAbstractApplicationService = oeServiceFactoryImpl
        .getOEApplicationServiceImpl(ubm.getSolutionType(),
                                   ubm.getEntityType(), 
                                   ubm.getSolutionTypeLevel2(), 
                                   ubm.getSolutionTypeLevel3());
    
    OEApplicationObjectSRO response = new OEApplicationObjectSRO();
}
```

**Step 2: UPI-Only Processing**
```java
if (upiFetchOnly && StringUtils.isNotEmpty(trackingId)) {
    // Check UPI SMS onboarding status
    SmsContent linkStatus = upiService.checkStatusSmsOnboarding(
        addCountryCodeInMobile(ubm.getMobileNumber()), 
        trackingId, 
        merchantCustId);
    
    merchantBankDetailsResponse.setBankAccountLinkStatus(linkStatus.getStatus());
    merchantBankDetailsResponse.setMessage(linkStatus.getRespMessage());
    
    // Return early if UPI linking failed
    if (!OEConstants.SUCCESS.equals(merchantBankDetailsResponse.getBankAccountLinkStatus())) {
        if (StringUtils.isEmpty(merchantBankDetailsResponse.getBankAccountLinkStatus()))
            merchantBankDetailsResponse.setMessage(linkStatus.getDisplayMessage());
        return merchantBankDetailsResponse;
    }
}
```

**Step 3: Comprehensive Bank Details Processing**
```java
if (!upiFetchOnly) {
    // Fetch related leads for comprehensive bank suggestions
    List<UserBusinessMapping> userBusinessMappings = fetchRelatedLeads(ubm, leadId);
    LOGGER.info("Populating rejected fields map");
    
    // Handle rejected leads
    if (oeValidator.isLeadRejected(ubm)) {
        oeApplicationServiceInternal.populateRejectedFieldsMap(response, ubm);
    }
    
    // Fetch suggested banks for non-small merchants
    if (!SolutionTypeLevel2.small_merchant.name().equals(ubm.getSolutionTypeLevel2())) {
        response.setSuggestedBanks(oeApplicationServiceInternal
            .fetchSuggestBanksForUserBusinessMappings(userBusinessMappings, 
                                                     ubm.getEntityType(), 
                                                     ubm.getCustId(), 
                                                     ubm, 
                                                     false));
    }
    
    // Prefetch individual details for specific solution types
    if (SolutionType.assisted_merchant_onboard.equals(ubm.getSolutionType())
            || SolutionType.qr_merchant.equals(ubm.getSolutionType())
            || SolutionType.merchant_common_onboard.equals(ubm.getSolutionType()) 
            || SolutionType.fse_diy.equals(ubm.getSolutionType()))
        prefetchIndividualDetails(response.getSuggestedBanks(), merchantCustId);
    
    // Special handling for PSA profile updates
    if (SolutionType.psa_profile_update.equals(ubm.getSolutionType())) {
        response.getSuggestedBanks().addAll(fetchBanksFromKyb(ubm.getCustId()));
        
        // Apply PSA bank restrictions
        List<String> restrictedBanksForPSA = redisReadThroughServiceImpl
            .getValueListThroughDB(OERedisConstants.RESTRICTED_BANKS_FOR_PSA);
        
        Set<BankDetailsSRO> bankDetailsSROS = response.getSuggestedBanks();
        for (BankDetailsSRO bankDetailsSRO : bankDetailsSROS) {
            bankDetailsSRO.setDisabledBank(String.valueOf(
                restrictedBanksForPSA.contains(bankDetailsSRO.getIfsc().toUpperCase())));
        }
        response.setSuggestedBanks(bankDetailsSROS);
    }
    
    // Populate bank details using appropriate service
    oeAbstractApplicationService.populateBankDetails(ubm.getSolutionType().getSolutionType(), 
                                                    response, 
                                                    ubm, 
                                                    userBusinessMappings);
}
```

**Step 4: Bank Logo Fetching**
```java
try {
    // Skip logo fetching for enterprise merchants
    if (!(SolutionType.enterprise_merchant_parent.name().equals(ubm.getSolutionType().getSolutionType()) 
          || SolutionType.enterprise_merchant_child.name().equals(ubm.getSolutionType().getSolutionType()))) {
        fetchBankLogos(response.getSuggestedBanks());
    }
} catch (IOException e) {
    LOGGER.error("error while fetching bank logos : " + e.getMessage());
}
```

**Step 5: Response Assembly**
```java
merchantBankDetailsResponse.setBankDetail(response.getBankDetails());
merchantBankDetailsResponse.setBankDetails(response.getSuggestedBanks());
LOGGER.info("merchantBankDetailsResponse : " + merchantBankDetailsResponse);

// Set solution type for merchant common onboard
if (SolutionType.merchant_common_onboard.equals(ubm.getSolutionType())) {
    merchantBankDetailsResponse.setLeadSolutionType(ubm.getSolutionType().getSolutionType());
}

return merchantBankDetailsResponse;
```

### **3. Supporting Methods**

#### **KYB Bank Details Fetching:**
```java
private Set<BankDetailsSRO> fetchBanksFromKyb(long custId) {
    Set<BankDetailsSRO> suggestBanks = new HashSet<>();
    KybDataResponse kybDataResponse = kybService.fetchKybData(custId);
    
    if (kybDataResponse != null && kybDataResponse.getRoles() != null) {
        for (KybDataResponse.Role role : kybDataResponse.getRoles()) {
            if (role.getContractDetails() != null) {
                for (KybDataResponse.ContractDetail contractDetails : role.getContractDetails()) {
                    if ((SolutionType.psa.getSolutionType().equalsIgnoreCase(contractDetails.getSolution())
                            || SolutionType.psa_diy.getSolutionType().equalsIgnoreCase(contractDetails.getSolution())) 
                            && contractDetails.getBankAccountDetail() != null) {
                        suggestBanks.add(oeConverterService
                            .getBankDetailsSROFromKYBBankAccountDetail(contractDetails.getBankAccountDetail()));
                    }
                }
            }
        }
    }
    return suggestBanks;
}
```

#### **Individual Details Prefetching:**
```java
private void prefetchIndividualDetails(Set<BankDetailsSRO> suggestBanks, String merchantCustId) {
    LOGGER.info("Executing prefetchIndividualDetails.");
    List<UserBusinessMapping> individualUbms = oeDao.getUserBusinessMappingByCustId(
        Long.valueOf(merchantCustId), EntityType.INDIVIDUAL.getEntityType());
    
    if (CollectionUtils.isNotEmpty(individualUbms)) {
        for (UserBusinessMapping ubm : individualUbms) {
            if (SolutionType.offline_50k.getSolutionType().equals(ubm.getSolutionType().getSolutionType())
                    || SolutionType.diy.getSolutionType().equals(ubm.getSolutionType().getSolutionType())) {
                
                BankDetails bankDetails = ubm.getRelatedBusinessSolutionMapping().getBankDetails();
                if (Objects.nonNull(bankDetails)) {
                    BankDetailsSRO bankDetailsSRO = oeConverterService.getBankDetailsSRO(bankDetails);
                    suggestBanks.add(bankDetailsSRO);
                }
            }
        }
    }
}
```

#### **Related Leads Fetching:**
```java
private List<UserBusinessMapping> fetchRelatedLeads(UserBusinessMapping ubm, String leadId) {
    List<UserBusinessMapping> userBusinessMappings = new ArrayList<>();
    userBusinessMappings.add(ubm);
    
    // Add related leads based on solution type
    if (SolutionType.enterprise_merchant_child.equals(ubm.getSolutionType())) {
        UserBusinessMapping parentUbm = ubmDao.fetchParentLeadForChild(leadId);
        if (Objects.nonNull(parentUbm)) {
            userBusinessMappings.add(parentUbm);
        }
    }
    
    return userBusinessMappings;
}
```

### **4. UPI Service Integration**

#### **UPI Status Checking:**
```java
public SmsContent checkStatusSmsOnboarding(String mobile, String trackingId, String merchantCustId) {
    // Check UPI SMS onboarding status
    UPIStatusCheckRequest request = new UPIStatusCheckRequest();
    request.setMobile(mobile);
    request.setTrackingId(trackingId);
    request.setMerchantCustId(merchantCustId);
    
    return upiService.checkUPILinkingStatus(request);
}
```

### **5. Database Operations**

#### **Lead Retrieval:**
```java
// Primary lead fetch
UserBusinessMapping ubm = ubmDao.getLeadByLeadId(leadId);

// Related leads fetch
List<UserBusinessMapping> userBusinessMappings = fetchRelatedLeads(ubm, leadId);

// Individual UBM fetch for prefetching
List<UserBusinessMapping> individualUbms = oeDao.getUserBusinessMappingByCustId(
    Long.valueOf(merchantCustId), EntityType.INDIVIDUAL.getEntityType());
```

#### **Bank Details Queries:**
```java
// Suggested banks from application service
Set<BankDetailsSRO> suggestedBanks = oeApplicationServiceInternal
    .fetchSuggestBanksForUserBusinessMappings(userBusinessMappings, 
                                             ubm.getEntityType(), 
                                             ubm.getCustId(), 
                                             ubm, 
                                             false);

// KYB bank details fetch
KybDataResponse kybDataResponse = kybService.fetchKybData(custId);
```

### **6. Configuration and Cache Management**

#### **Redis Configuration:**
```java
// PSA bank restrictions
List<String> restrictedBanksForPSA = redisReadThroughServiceImpl
    .getValueListThroughDB(OERedisConstants.RESTRICTED_BANKS_FOR_PSA);

// Customer ID and mobile validation flag
boolean validationFlag = ((OEStartupCache) OECacheManager.getInstance().getCache(OEStartupCache.class))
    .getCustIdAndMobileValidationFlag();
```

### **7. Solution Type Specific Processing**

#### **Solution Type Routing:**
1. **Small Merchant:** Skip suggested banks fetching
2. **Assisted Merchant Onboard:** Include individual details prefetching
3. **QR Merchant:** Include individual details prefetching
4. **Merchant Common Onboard:** Include individual details and solution type setting
5. **FSE DIY:** Include individual details prefetching
6. **PSA Profile Update:** Include KYB banks and restrictions
7. **Enterprise Parent/Child:** Skip bank logo fetching

#### **Entity Type Processing:**
- **Individual:** Prefetch from offline_50k and DIY solutions
- **Business:** Standard suggested banks processing
- **Merchant:** Comprehensive bank details population

### **8. Response Structure**

#### **MerchantBankDetailsResponse:**
```java
public class MerchantBankDetailsResponse {
    private int statusCode;                    // HTTP status code
    private String successMsg;                 // Success message
    private Set<BankDetailsSRO> bankDetails;   // Suggested bank details
    private BankDetailsSRO bankDetail;         // Primary bank detail
    private String bankAccountLinkStatus;      // UPI linking status
    private String message;                    // Response message
    private String leadSolutionType;           // Lead solution type
}
```

#### **BankDetailsSRO Structure:**
```java
public class BankDetailsSRO {
    private String bankAccountNumber;          // Account number
    private String ifsc;                       // IFSC code
    private String bankName;                   // Bank name
    private String bankAccountHolder;          // Account holder name
    private String nameMatchStatus;            // Name match status
    private String bankDetailsUuid;            // Unique identifier
    private String disabledBank;               // Bank restriction status
    private String logoUrl;                    // Bank logo URL
}
```

### **9. Error Handling**

#### **Validation Errors:**
- **Invalid Lead ID:** BadRequestException with INVALID_LEAD_ID message
- **Mobile Number Validation:** BadRequestException with VALIDATION_ERROR
- **Null Parameters:** BadRequestException with specific null parameter messages

#### **Service Errors:**
- **UPI Service Failures:** Graceful handling with status message
- **KYB Service Failures:** Continue processing without KYB banks
- **Bank Logo Fetch Failures:** Log error and continue

#### **Controller Error Handling:**
- **BadRequestException:** Return 400 with error message
- **General Exception:** Return 500 with internal server error message

### **10. Performance Optimization**

#### **Caching Strategy:**
- **OEStartupCache:** Configuration flags and validation settings
- **Redis Cache:** PSA bank restrictions and other configuration data
- **Service Factory Caching:** Reuse of application service instances

#### **Lazy Loading:**
- **Bank Details:** Loaded only when needed
- **Individual UBMs:** Fetched only for specific solution types
- **Bank Logos:** Fetched asynchronously to avoid blocking

#### **Conditional Processing:**
- **UPI Only Mode:** Skip comprehensive bank processing
- **Solution Type Checks:** Execute only relevant processing paths
- **Entity Type Filtering:** Process only applicable data

## 🔑 **Key Technical Concepts**

### **1. Multi-Mode Operation**
- **UPI-Only Mode:** Quick status check for UPI operations
- **Comprehensive Mode:** Full bank details with suggestions and logos
- **Conditional Processing:** Based on solution type and entity type

### **2. Solution Type Aware Processing**
- **Dynamic Service Selection:** Factory pattern for service resolution
- **Type-Specific Logic:** Custom processing for each solution type
- **Entity Type Integration:** Different processing for Individual vs Business

### **3. Bank Suggestion Engine**
- **Related Leads Analysis:** Include parent/child lead relationships
- **Historical Data Integration:** Previous bank details from related solutions
- **KYB Data Integration:** Bank details from Know Your Business service

### **4. UPI Integration Framework**
- **SMS Onboarding Status:** Track UPI account linking progress
- **Mobile Number Processing:** Country code addition and validation
- **Tracking Reference:** Correlation with external UPI systems

### **5. Configuration-Driven Restrictions**
- **PSA Bank Restrictions:** Redis-based restriction management
- **Solution Type Filtering:** Conditional feature enablement
- **Entity Type Validation:** Role-based data access

## 📊 **Service Integration Architecture**

### **Core Services:**
1. **MerchantBankDetailsService:** Main orchestration service
2. **OEApplicationServiceInternal:** Suggested banks retrieval
3. **UPIService:** UPI operations and status checking
4. **KYBService:** Know Your Business bank data
5. **OEConverterService:** Data transformation and mapping

### **Data Access Layer:**
1. **UserBusinessMappingDao:** Lead and UBM operations
2. **OEDao:** General OE data access
3. **RedisReadThroughService:** Configuration and cache management

### **External Integrations:**
1. **UPI Gateway:** UPI account linking and status
2. **KYB Service:** Business bank account verification
3. **Bank Logo Service:** Bank branding and visual assets

## 🚀 **Operational Features**

### **Performance Metrics:**
- **Response Time:** Bank details retrieval speed
- **Cache Hit Rate:** Configuration cache effectiveness
- **UPI Success Rate:** UPI linking operation success
- **Suggestion Accuracy:** Relevant bank suggestion percentage

### **Monitoring Points:**
- **Service Availability:** UPI and KYB service health
- **Error Rate:** Failed bank retrieval operations
- **Data Quality:** Bank details completeness and accuracy
- **User Experience:** Response time and suggestion relevance

### **Scalability Features:**
- **Lazy Loading:** On-demand data fetching
- **Conditional Processing:** Skip unnecessary operations
- **Cache Utilization:** Reduce database load
- **Service Factory Pattern:** Efficient service instance management

This comprehensive analysis demonstrates the sophisticated merchant bank details retrieval system that combines UPI integration, intelligent bank suggestions, solution type awareness, and performance optimization to provide a seamless banking experience in the Paytm OE ecosystem.
