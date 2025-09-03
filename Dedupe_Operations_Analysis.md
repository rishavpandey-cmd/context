# Dedupe Operations Analysis - Complete Documentation

## Overview
This document provides a comprehensive analysis of the `/dedupe` endpoint in the Paytm OE (Onboarding Engine) system, which handles email and mobile number deduplication checks against the marketplace (seller service) to ensure merchant credentials are unique before registration.

## Architecture Summary
The dedupe system implements a multi-layered validation architecture:
1. **Controller Layer** - HTTP endpoint handling and initial validation
2. **Service Factory Layer** - Dynamic service resolution based on solution/entity type
3. **Abstract Service Layer** - OAuth and marketplace validation orchestration
4. **Marketplace Service Layer** - Direct integration with seller service APIs
5. **OAuth Service Layer** - Email validation against OAuth system

---

## Endpoint Analysis

### POST /dedupe - Merchant Credentials Deduplication

**File:** `SolutionLeadController.java`  
**Method:** `merchantDedupeInMarketPlace()`  
**Lines:** 250-269  
**Endpoint:** `POST /panel/v1/solution/dedupe`

#### Purpose:
Check if merchant's email and mobile number are unique at the seller service (marketplace) before allowing registration.

#### Parameters:
- `entityType` (String, required) - Type of entity (INDIVIDUAL, PROPRIETORSHIP, etc.)
- `solution` (String, required) - Solution type identifier
- `channel` (String, optional) - Channel identifier (defaults to OE_PANEL)
- `solutionDetails` (SolutionLeadRequest, body) - Contains email and/or mobile number to validate

#### Processing Flow:
```java
@RequestMapping(value = "/dedupe", method = RequestMethod.POST)
public ResponseEntity merchantDedupeInMarketPlace(
    @RequestParam(value = "entityType") String entityType,
    @RequestParam(value = "solution") String solution,
    @RequestParam(value = "channel") String channel,
    @RequestBody SolutionLeadRequest solutionDetails) {
    
    // Set default channel
    if (StringUtils.isBlank(channel)) {
        channel = Channel.OE_PANEL.name();
    }
    
    // Route to appropriate service implementation
    BaseResponse response = oeServiceFactory.getOESolutionServiceFromServiceFactory(
        SolutionType.valueOf(solution), 
        EntityType.valueOf(entityType),
        Channel.valueOf(channel)
    ).validateCredentials(solution, entityType, channel, solutionDetails);
    
    return ResponseEntity.status(response.getStatusCode()).body(response);
}
```

---

## Service Layer Deep Dive

### OEAbstractSolutionLeadServiceImpl Analysis

**File:** `OEAbstractSolutionLeadServiceImpl.java`  
**Primary Method:** `validateCredentials()`  
**Lines:** 113-122

#### Decision Logic:
The service implements intelligent routing based on channel, solution type, and data availability:

```java
public BaseResponse validateCredentials(String solution, String entityType, String channel, SolutionLeadRequest solutionDetails) throws Exception {
    List<Channel> oauthValidationChannels = Arrays.asList(Channel.OE_PANEL, Channel.SELLER_PANEL);

    if(oauthValidationChannels.contains(Channel.valueOf(channel)) &&
            SolutionType.getMarketplaceSolutions().contains(SolutionType.valueOf(solution)) &&
            !org.springframework.util.StringUtils.isEmpty(solutionDetails.getEmail()) ) {
        return validateFromOAuthAndMarketplace(solution, entityType, solutionDetails);
    }
    return merchantDedupeInMarketPlace(solution, entityType, solutionDetails);
}
```

#### Two Validation Paths:

1. **OAuth + Marketplace Path** (Enhanced Validation)
   - **Conditions:** 
     - Channel is OE_PANEL or SELLER_PANEL
     - Solution is a marketplace solution
     - Email is provided
   - **Process:** OAuth validation followed by marketplace dedupe

2. **Standard Marketplace Path** (Basic Validation)
   - **Conditions:** All other cases
   - **Process:** Direct marketplace dedupe validation

---

## Validation Paths Detailed Analysis

### Path 1: OAuth + Marketplace Validation

**Method:** `validateFromOAuthAndMarketplace()`  
**Lines:** 139-159

#### Step 1: OAuth Request Validation
```java
private BaseResponse validateRequestForOAuth(String solution, String entityType, SolutionLeadRequest solutionDetails) {
    if (StringUtils.isBlank(solutionDetails.getEmail())) {
        return handleError(new BaseResponse(), HttpStatus.SC_BAD_REQUEST, ErrorMessages.INCOMPLETE_PAYLOAD);
    }
    
    Map<ValidationFieldsEnum, String> validationMap = new HashMap<>();
    validationMap.put(ValidationFieldsEnum.EMAIL, solutionDetails.getEmail());
    
    try {
        regexValidationService.validate(entityType, solution, validationMap);
    } catch (ValidationException e) {
        return handleError(new BaseResponse(), HttpStatus.SC_BAD_REQUEST, e.getMessage());
    }
    return null;
}
```

**Validations:**
- Email presence check
- Email format validation using regex
- Entity and solution-specific validation rules

#### Step 2: OAuth Service Integration
```java
oauthResponse = oauthService.validateEmailFromOauth(solutionDetails.getEmail());
```

**Purpose:** Verify if the email exists in the OAuth system  
**Response:** `OAuthFetchUserDetailsResponse`

#### Step 3: Marketplace Validation
If OAuth validation passes, proceed with standard marketplace dedupe validation.

#### Step 4: Combined Response
```java
if(response.getStatusCode() != HttpStatus.OK.value())
    return response;
oauthResponse.setDisplayMessage("Oauth and Marketplace Validation Passed");
return oauthResponse;
```

### Path 2: Standard Marketplace Validation

**Method:** `merchantDedupeInMarketPlace()`  
**Lines:** 170-218

#### Step 1: Request Validation
```java
private BaseResponse validateRequest(String solution, String entityType, SolutionLeadRequest solutionDetails) {
    if (StringUtils.isBlank(solutionDetails.getEmail()) && StringUtils.isBlank(solutionDetails.getMobileNumber())) {
        return handleError(new BaseResponse(), HttpStatus.SC_BAD_REQUEST, ErrorMessages.INCOMPLETE_PAYLOAD);
    }
    
    Map<ValidationFieldsEnum, String> validationMap = new HashMap<>();
    if (StringUtils.isNotBlank(solutionDetails.getEmail())) {
        validationMap.put(ValidationFieldsEnum.EMAIL, solutionDetails.getEmail());
    }
    if (StringUtils.isNotBlank(solutionDetails.getMobileNumber())) {
        validationMap.put(ValidationFieldsEnum.MOBILE, solutionDetails.getMobileNumber());
    }
    
    try {
        regexValidationService.validate(entityType, solution, validationMap);
    } catch (ValidationException e) {
        return handleError(new BaseResponse(), HttpStatus.SC_BAD_REQUEST, e.getMessage());
    }
    return null;
}
```

**Requirements:**
- At least one credential (email OR mobile) must be provided
- Format validation for provided credentials

#### Step 2: Email Dedupe Validation (if email provided)
```java
if (StringUtils.isNotBlank(solutionDetails.getEmail())) {
    MarketPlaceMerchantDedupeResponse marketPlaceMerchantEmailDedupeResponse = 
        marketPlaceService.dedupeMarketPlaceMerchant(solutionDetails.getEmail(), null);
    
    boolean isValid = org.apache.http.HttpStatus.SC_OK == marketPlaceMerchantEmailDedupeResponse.getStatusCode()
            && Objects.isNull(marketPlaceMerchantEmailDedupeResponse.getError());
    
    if (!isValid) {
        int errorCode = org.apache.http.HttpStatus.SC_INTERNAL_SERVER_ERROR;
        String errorMessage = ErrorMessages.FETCH_MERCHANT_DETAILS_FAILED_MARKETPLACE;

        if (org.apache.http.HttpStatus.SC_OK == marketPlaceMerchantEmailDedupeResponse.getStatusCode()) {
            errorCode = org.apache.http.HttpStatus.SC_EXPECTATION_FAILED;
            errorMessage = marketPlaceMerchantEmailDedupeResponse.getError();
        }
        return handleError(new BaseResponse(), errorCode, errorMessage);
    }
}
```

**Process:**
- Call `marketPlaceService.dedupeMarketPlaceMerchant(email, null)`
- Check response status and error presence
- Return specific error if email already exists

#### Step 3: Mobile Dedupe Validation (if mobile provided)
```java
if (StringUtils.isNotBlank(solutionDetails.getMobileNumber())) {
    MarketPlaceMerchant marketplaceMerchantDetailsFromMobileResponse = 
        marketPlaceService.fetchMerchantDetailsFromMobile(solutionDetails.getMobileNumber());
    
    MarketPlaceValidationResponse marketPlaceMobileValidationResponse = 
        oeServiceFactory.getOEApplicationServiceImpl(SolutionType.valueOf(solution),
            EntityType.valueOf(entityType)).getMerchantStatusOnMarketPlace(
                marketplaceMerchantDetailsFromMobileResponse, 
                solutionDetails.getPan(),
                SolutionType.valueOf(solution));

    boolean isValid = (MarketPlaceValidationEnum.SUCCESSFUL == marketPlaceMobileValidationResponse.isStatus()
            && Objects.isNull(marketplaceMerchantDetailsFromMobileResponse.getMerchant()))
            || MarketPlaceValidationEnum.PARTIAL == marketPlaceMobileValidationResponse.isStatus();
    
    if (!isValid) {
        String errorMessage = marketPlaceMobileValidationResponse.getError();
        if (MarketPlaceValidationEnum.UNSUCCESSFUL == marketPlaceMobileValidationResponse.isStatus()
                && Objects.nonNull(marketplaceMerchantDetailsFromMobileResponse.getMerchant())) {
            errorMessage = "Mobile Number Already Exist";
        }
        return handleError(new BaseResponse(), org.apache.http.HttpStatus.SC_EXPECTATION_FAILED, errorMessage);
    }
}
```

**Process:**
1. **Fetch Merchant by Mobile:** `fetchMerchantDetailsFromMobile()`
2. **Validate Merchant Status:** `getMerchantStatusOnMarketPlace()`
3. **Business Logic Check:** 
   - SUCCESS + no merchant = Available
   - PARTIAL = Conditionally available
   - All other cases = Already exists

#### Step 4: Success Response
```java
return handleError(new BaseResponse(), org.apache.http.HttpStatus.SC_OK, "Dedupe Passed.");
```

---

## Marketplace Service Integration

### IMarketPlaceService Interface

**File:** `IMarketPlaceService.java`

#### Key Methods for Dedupe:

1. **Email Dedupe:**
   ```java
   MarketPlaceMerchantDedupeResponse dedupeMarketPlaceMerchant(String email, String custId) throws Exception;
   ```

2. **Mobile Dedupe:**
   ```java
   MarketPlaceMerchant fetchMerchantDetailsFromMobile(String mobileNo) throws Exception;
   ```

3. **Email Validation:**
   ```java
   BaseResponse validateEmailIdFromMarketPlace(String email, String mobileNo);
   ```

### Response Objects

#### MarketPlaceMerchantDedupeResponse
```java
{
    "statusCode": 200,
    "error": null,  // null = email available, string = error message
    "message": "Success"
}
```

#### MarketPlaceMerchant
```java
{
    "merchant": {
        "merchantId": "12345",
        "email": "merchant@example.com",
        "mobile": "+919876543210",
        "status": "ACTIVE"
    }
}
```

#### MarketPlaceValidationResponse
```java
{
    "status": "SUCCESSFUL|PARTIAL|UNSUCCESSFUL",
    "error": "Error message if validation failed"
}
```

---

## Error Handling Strategy

### Error Response Mapping

| Scenario | HTTP Status | Error Message |
|----------|-------------|---------------|
| Missing email/mobile | 400 BAD_REQUEST | "Incomplete payload" |
| Invalid email format | 400 BAD_REQUEST | Regex validation error |
| Invalid mobile format | 400 BAD_REQUEST | Regex validation error |
| OAuth validation failed | 500 INTERNAL_SERVER_ERROR | OAuth error message |
| Email already exists | 417 EXPECTATION_FAILED | Marketplace error message |
| Mobile already exists | 417 EXPECTATION_FAILED | "Mobile Number Already Exist" |
| Marketplace service error | 500 INTERNAL_SERVER_ERROR | "Failed to fetch merchant details" |
| Validation successful | 200 OK | "Dedupe Passed." |
| OAuth + Marketplace success | 200 OK | "Oauth and Marketplace Validation Passed" |

### Error Response Format

#### Standard Error:
```json
{
    "statusCode": 417,
    "displayMessage": "Email already registered with marketplace"
}
```

#### Success Response:
```json
{
    "statusCode": 200,
    "displayMessage": "Dedupe Passed."
}
```

#### OAuth Success Response:
```json
{
    "statusCode": 200,
    "displayMessage": "Oauth and Marketplace Validation Passed",
    "userDetails": {
        "email": "user@example.com",
        "emailVerified": true
    }
}
```

---

## Validation Rules and Business Logic

### Channel-Based Routing

| Channel | OAuth Required | Marketplace Check | Notes |
|---------|----------------|-------------------|-------|
| OE_PANEL | Yes (if marketplace solution + email) | Yes | Enhanced validation |
| SELLER_PANEL | Yes (if marketplace solution + email) | Yes | Enhanced validation |
| Others | No | Yes | Standard validation only |

### Solution Type Considerations

**Marketplace Solutions:**
- Enhanced validation with OAuth integration
- Stricter email validation requirements
- Cross-platform dedupe checks

**Non-Marketplace Solutions:**
- Standard marketplace dedupe only
- Basic format validation
- Solution-specific validation rules

### Mobile Validation States

| Validation State | Merchant Present | Interpretation |
|------------------|------------------|----------------|
| SUCCESSFUL | null | Mobile available |
| SUCCESSFUL | object | Mobile already exists |
| PARTIAL | any | Conditionally available |
| UNSUCCESSFUL | any | Validation failed |

---

## Performance Considerations

### Caching Strategy
- **Service Bean Caching:** Factory pattern with cached service implementations
- **Validation Rules Caching:** Regex patterns and business rules cached
- **No Response Caching:** Real-time validation required for accuracy

### External Service Integration
- **Marketplace API:** Real-time calls to seller service
- **OAuth Service:** Real-time email validation
- **Timeout Handling:** Service-level timeout management
- **Retry Logic:** Built into marketplace service layer

### Database Impact
- **No Direct Database Queries:** All validation via external services
- **Audit Logging:** Request/response logging for debugging
- **No State Storage:** Stateless validation process

---

## Security Measures

### Data Protection
- **Input Sanitization:** Email and mobile format validation
- **Parameter Validation:** Required field checks
- **Error Message Sanitization:** No sensitive data in error responses

### API Security
- **Channel Validation:** Authorized channels only
- **Rate Limiting:** External service integration includes rate limiting
- **Audit Trail:** Complete request/response logging

---

## Integration Patterns

### Service Factory Pattern
```java
// Dynamic service resolution based on solution/entity type
OEAbstractSolutionLeadServiceImpl service = oeServiceFactory.getOESolutionServiceFromServiceFactory(
    SolutionType.valueOf(solution), 
    EntityType.valueOf(entityType),
    Channel.valueOf(channel)
);
```

### Strategy Pattern
```java
// Different validation strategies based on channel and solution
if (isOAuthRequired(channel, solution, email)) {
    return oauthAndMarketplaceValidation();
} else {
    return standardMarketplaceValidation();
}
```

### Template Method Pattern
```java
// Common validation template with customizable steps
public BaseResponse validateCredentials() {
    validateRequest();      // Common
    validateOAuth();        // Optional
    validateMarketplace();  // Common
    return response();      // Common
}
```

---

## Monitoring and Debugging

### Logging Strategy
```java
// Key logging points
LOGGER.info("Request Received To Check Dedupe At Seller Service - " + solutionDetails);
LOGGER.info("MarketPlaceMerchantDedupeResponse For Email - " + emailResponse);
LOGGER.info("MarketPlaceMerchant Details For Mobile - " + mobileResponse);
LOGGER.info("MarketPlaceValidationResponse - " + validationResponse);
```

### Error Tracking
- **Exception Handling:** Comprehensive try-catch blocks
- **Error Classification:** Business vs. technical errors
- **Response Mapping:** Consistent error response format

---

## Configuration Management

### Channel Configuration
```java
List<Channel> oauthValidationChannels = Arrays.asList(Channel.OE_PANEL, Channel.SELLER_PANEL);
```

### Solution Type Configuration
```java
SolutionType.getMarketplaceSolutions().contains(SolutionType.valueOf(solution))
```

### Validation Rules
- **Regex Patterns:** Entity and solution-specific validation
- **Business Rules:** Marketplace-specific validation logic
- **Error Messages:** Configurable error message templates

---

## Testing Scenarios

### Positive Test Cases
1. **New Email/Mobile:** Both available → Success
2. **OAuth + Marketplace:** Valid email + available mobile → Enhanced success
3. **Email Only:** Valid new email → Success
4. **Mobile Only:** Valid new mobile → Success

### Negative Test Cases
1. **Duplicate Email:** Email exists → EXPECTATION_FAILED
2. **Duplicate Mobile:** Mobile exists → EXPECTATION_FAILED
3. **Invalid Format:** Malformed email/mobile → BAD_REQUEST
4. **Missing Data:** No email or mobile → BAD_REQUEST
5. **OAuth Failure:** OAuth service error → INTERNAL_SERVER_ERROR
6. **Marketplace Error:** Service unavailable → INTERNAL_SERVER_ERROR

### Edge Cases
1. **Partial Mobile Validation:** Mobile in transitional state
2. **OAuth + Marketplace Mismatch:** OAuth passes but marketplace fails
3. **Network Timeouts:** External service timeouts
4. **Multiple Error Conditions:** Both email and mobile issues

---

## Key Files and References

| Component | File | Key Methods | Lines |
|-----------|------|-------------|-------|
| Controller | SolutionLeadController.java | merchantDedupeInMarketPlace() | 250-269 |
| Abstract Service | OEAbstractSolutionLeadServiceImpl.java | validateCredentials(), validateFromOAuthAndMarketplace(), merchantDedupeInMarketPlace() | 113-218 |
| Marketplace Interface | IMarketPlaceService.java | dedupeMarketPlaceMerchant(), fetchMerchantDetailsFromMobile() | 12, 32 |
| Service Factory | OEServiceFactoryImpl.java | getOESolutionServiceFromServiceFactory() | 677-679 |

---

## Conclusion

The `/dedupe` endpoint demonstrates a sophisticated multi-layered validation system with:

- **Intelligent Routing:** Channel and solution-based validation strategies
- **Dual Validation Paths:** OAuth + Marketplace vs. Standard marketplace validation
- **Comprehensive Error Handling:** Detailed error classification and response mapping
- **External Service Integration:** Real-time validation against marketplace and OAuth services
- **Security Measures:** Input validation, sanitization, and audit logging
- **Performance Optimization:** Service caching and efficient external service calls
- **Flexible Configuration:** Channel, solution, and validation rule configuration

This architecture ensures merchant credential uniqueness while providing a robust, scalable, and maintainable validation framework for the Paytm OE system.
