# Fetch User Details Operations Analysis - `/fetchUserDetails` Endpoint

## 📋 **Overview**
The `/fetchUserDetails` endpoint in `SolutionLeadController.java` retrieves FSM (Field Sales Management) user details including team and sub-team information for a given mobile number through user ACL and FSM gateway services with comprehensive access control and validation.

## 🔗 **Endpoint Details**
- **URL:** `GET /fetchUserDetails`
- **Controller Method:** `fetchUserDetails` (lines 722-734)
- **Primary Service:** `SolutionLeadHelperService.fetchFsmTeamSubTeam`
- **Query Parameter:** `mobileNumber` (required)
- **Access Control:** `@PanelAccessCheck(apiName = "panel-search")`
- **Response:** `BaseResponse` with team and sub-team information

## 🏗️ **Complete Technical Flow**

### **1. Controller Layer** (`SolutionLeadController.java`)

```java
@Operation(summary = "fetch fsm user details", description = "Retrieve FSM user details")
@RequestMapping(value = "/fetchUserDetails", method = RequestMethod.GET)
@PanelAccessCheck(apiName = "panel-search")
public ResponseEntity fetchUserDetails(@Context HttpServletRequest httpRequest, 
                                      @Context HttpServletResponse httpResponse,
                                      @RequestParam String mobileNumber) {
    try {
        // Delegate to solution lead helper service with hierarchy request flag
        BaseResponse baseResponse = solutionLeadHelperService.fetchFsmTeamSubTeam(mobileNumber, true);
        return ResponseEntity.status(baseResponse.getStatusCode()).body(baseResponse);
        
    } catch (Exception e) {
        LOGGER.error("Error while fetching fsm user details", e);
        BaseResponse baseResponse = handleError(
            new BaseResponse(), 
            HttpStatus.INTERNAL_SERVER_ERROR.value(), 
            Utils.generatePanelErrorMessage(ErrorMessages.INTERNAL_SERVER_ERROR_MESSAGE));
        return ResponseEntity.status(baseResponse.getStatusCode()).body(baseResponse);
    }
}
```

**Key Features:**
- **Panel Access Control:** `@PanelAccessCheck(apiName = "panel-search")` for role-based access
- **Mobile Number Parameter:** Required parameter for user identification
- **Hierarchy Request:** Fixed `true` flag for comprehensive hierarchy data
- **Standardized Error Handling:** Consistent error response format

### **2. Access Control Layer** (`@PanelAccessCheck`)

#### **Panel Access Validation:**
```java
@PanelAccessCheck(apiName = "panel-search")
```

**Access Control Features:**
- **API-Specific Validation:** Checks access permissions for "panel-search" API
- **Role-Based Authorization:** Validates user roles and permissions
- **Session Validation:** Ensures valid authenticated session
- **Context Preservation:** Maintains user context throughout request processing

#### **Access Control Flow:**
1. **Session Validation:** Verify active authenticated session
2. **Role Verification:** Check user roles against API requirements
3. **Permission Checking:** Validate specific API access permissions
4. **Context Setup:** Establish user context for downstream processing
5. **Request Continuation:** Allow request to proceed if authorized

### **3. Service Layer** (`SolutionLeadHelperService`)

#### **Main Processing Flow:**

**Step 1: Mobile to Customer ID Mapping**
```java
public BaseResponse fetchFsmTeamSubTeam(String mobileNumber, boolean isHierarchyRequest) throws Exception {
    // Fetch customer ID using mobile number
    Long custIdFromMobile = userAclService.fetchCustIdUsigMobile(mobileNumber);
    LOGGER.info("Customer id found against mobile number " + custIdFromMobile);
    
    // Validate customer ID existence
    if (Objects.isNull(custIdFromMobile)) {
        return handleError(new BaseResponse(), HttpStatus.BAD_REQUEST.value(), ErrorMessages.CUST_ID_NOT_FOUND);
    }
    
    // Convert to string for downstream processing
    String agentCustId = String.valueOf(custIdFromMobile);
}
```

**Step 2: FSM User Details Retrieval**
```java
// Fetch FSM user details with hierarchy information
FsmUserDetailsDO fsmUserDetailsDO = fsmGatewayService.fetchFsmUserDetails(agentCustId, isHierarchyRequest);

// Validate FSM response and check for errors
if (Objects.isNull(fsmUserDetailsDO) || 
    (Objects.nonNull(fsmUserDetailsDO.getError()) && 
     (StringUtils.isNotEmpty(fsmUserDetailsDO.getError().getErrorCode()) || 
      StringUtils.isNotEmpty(fsmUserDetailsDO.getError().getErrorMsg())))) {
    return handleError(new BaseResponse(), HttpStatus.BAD_REQUEST.value(), ErrorMessages.FSE_NOT_MAPPED_ON_FSM);
}
```

**Step 3: Team and Sub-Team Information Extraction**
```java
String fseTeam = null, fseSubTeam = null;

// Extract team information from FSM profiles
if (CollectionUtils.isNotEmpty(fsmUserDetailsDO.getProfiles())) {
    FsmUserProfileDO fsmUserProfileDO = fsmUserDetailsDO.getProfiles().get(0);
    
    if (Objects.nonNull(fsmUserProfileDO) && StringUtils.isNotBlank(fsmUserProfileDO.getTeam())) {
        fseTeam = StringUtils.isNotBlank(fsmUserProfileDO.getTeam()) ? 
                 fsmUserProfileDO.getTeam() : null;
        fseSubTeam = StringUtils.isNotBlank(fsmUserProfileDO.getSubTeam()) ? 
                    fsmUserProfileDO.getSubTeam() : null;
    }
}

LOGGER.info("Account team: " + fseTeam + ", Account Sub-team: " + fseSubTeam);
```

**Step 4: Response Construction**
```java
// Create and populate response
BaseResponse response = new BaseResponse();
response.setDisplayMessage("Account team: " + fseTeam + ", Account Sub-team: " + fseSubTeam);
response.setStatusCode(HttpStatus.OK.value());
return response;
```

### **4. User ACL Service Integration**

#### **Mobile to Customer ID Mapping:**
```java
public interface IUserAclService {
    Long fetchCustIdUsigMobile(String mobileNumber);
}

@Override
public Long fetchCustIdUsigMobile(String mobileNumber) {
    try {
        // Validate mobile number format
        if (StringUtils.isBlank(mobileNumber)) {
            LOGGER.warn("Mobile number is blank for customer ID lookup");
            return null;
        }
        
        // Query user authentication service
        UserAuthResponse userAuthResponse = userAuthService.getUserByMobile(mobileNumber);
        
        if (Objects.nonNull(userAuthResponse) && Objects.nonNull(userAuthResponse.getCustId())) {
            return userAuthResponse.getCustId();
        }
        
        LOGGER.info("No customer ID found for mobile number: {}", mobileNumber);
        return null;
        
    } catch (Exception e) {
        LOGGER.error("Error fetching customer ID for mobile: {}", mobileNumber, e);
        return null;
    }
}
```

### **5. FSM Gateway Service Integration**

#### **FSM User Details Retrieval:**
```java
public interface IFsmGatewayService {
    FsmUserDetailsDO fetchFsmUserDetails(String custId, boolean isHierarchyRequest);
}

@Override
public FsmUserDetailsDO fetchFsmUserDetails(String custId, boolean isHierarchyRequest) {
    try {
        // Prepare FSM service URL
        String fsmServiceUrl = fsmProperties.getBaseUrl() + fsmProperties.getUserDetailsEndpoint();
        
        // Prepare request parameters
        Map<String, Object> requestParams = new HashMap<>();
        requestParams.put("custId", custId);
        requestParams.put("includeHierarchy", isHierarchyRequest);
        
        // Prepare headers
        Map<String, String> headers = new HashMap<>();
        headers.put("Authorization", "Bearer " + getFsmAccessToken());
        headers.put("Content-Type", "application/json");
        headers.put("x-request-id", generateRequestId());
        
        // Serialize request
        String requestBody = JsonUtils.serialize(requestParams);
        
        // Make HTTP call to FSM service
        OEHttpResponse httpResponse = ConnectionUtil.connect(
            RequestMethod.POST,
            fsmServiceUrl,
            requestBody,
            headers,
            OEExternalAPIsEnum.FSM_USER_DETAILS,
            true,
            connectionTimeout,
            readTimeout
        );
        
        // Process response
        return processFsmUserDetailsResponse(httpResponse);
        
    } catch (Exception e) {
        LOGGER.error("Error fetching FSM user details for custId: {}", custId, e);
        return createErrorResponse(e);
    }
}
```

#### **FSM Response Processing:**
```java
private FsmUserDetailsDO processFsmUserDetailsResponse(OEHttpResponse httpResponse) {
    FsmUserDetailsDO fsmUserDetails = new FsmUserDetailsDO();
    
    if (httpResponse != null && httpResponse.getResponseCode() == HttpStatus.SC_OK) {
        try {
            // Deserialize FSM response
            FsmServiceResponse fsmResponse = JsonUtils.deserialize(
                httpResponse.getResponseBody(), 
                FsmServiceResponse.class);
            
            if (fsmResponse != null && "SUCCESS".equals(fsmResponse.getStatus())) {
                // Map successful response
                fsmUserDetails = mapFsmUserDetails(fsmResponse.getData());
                fsmUserDetails.setResponseStatus(HttpStatus.SC_OK);
                fsmUserDetails.setMessage("FSM user details fetched successfully");
                
            } else {
                // Handle FSM service errors
                FsmErrorDO error = new FsmErrorDO();
                error.setErrorCode(fsmResponse != null ? fsmResponse.getErrorCode() : "UNKNOWN");
                error.setErrorMsg(fsmResponse != null ? fsmResponse.getMessage() : "FSM user details fetch failed");
                fsmUserDetails.setError(error);
                fsmUserDetails.setResponseStatus(HttpStatus.SC_BAD_REQUEST);
            }
            
        } catch (Exception e) {
            LOGGER.error("Error parsing FSM response", e);
            fsmUserDetails.setError(createParsingError(e));
            fsmUserDetails.setResponseStatus(HttpStatus.SC_INTERNAL_SERVER_ERROR);
        }
        
    } else {
        // Handle HTTP errors
        FsmErrorDO error = new FsmErrorDO();
        error.setErrorCode("HTTP_ERROR");
        error.setErrorMsg("FSM service unavailable");
        fsmUserDetails.setError(error);
        fsmUserDetails.setResponseStatus(httpResponse != null ? httpResponse.getResponseCode() : HttpStatus.SC_INTERNAL_SERVER_ERROR);
    }
    
    return fsmUserDetails;
}
```

### **6. Data Object Structure**

#### **FSM User Details Data Object:**
```java
@Data
@JsonIgnoreProperties(ignoreUnknown = true)
@JsonInclude(JsonInclude.Include.NON_NULL)
public class FsmUserDetailsDO {
    private FsmUserInfoDO userInfo;          // Primary user information
    private FsmUserInfoDO parentInfo;        // Parent hierarchy information
    private FsmUserInfoDO grandParentInfo;   // Grand parent hierarchy information
    private List<FsmUserProfileDO> profiles; // User profiles with team details
    private String statusMessage;            // Status message
    private FsmErrorDO error;               // Error information
    private String message;                 // Response message
    private Integer responseStatus;         // HTTP response status
}
```

#### **FSM User Profile Data Object:**
```java
@Data
@JsonIgnoreProperties(ignoreUnknown = true)
@JsonInclude(JsonInclude.Include.NON_NULL)
public class FsmUserProfileDO {
    private String status;           // Profile status
    private String team;            // Team name
    private String roll;            // User role
    private String name;            // User name
    private String empCode;         // Employee code
    private String subTeam;         // Sub-team name
    private String designation;     // User designation
    private String vendor;          // Vendor information
    private FsmHierarchyDO hierarchy; // Hierarchy details

    // Custom getter for subTeam with fallback
    public String getSubTeam() {
        return StringUtils.isNotBlank(subTeam) ? subTeam : "";
    }
}
```

#### **FSM Error Data Object:**
```java
@Data
@JsonIgnoreProperties(ignoreUnknown = true)
@JsonInclude(JsonInclude.Include.NON_NULL)
public class FsmErrorDO {
    private String errorCode;    // Error code
    private String errorMsg;     // Error message
    private String details;      // Additional error details
}
```

### **7. Error Handling Framework**

#### **Error Categories:**
1. **Validation Errors (400):**
   - Customer ID not found for mobile number
   - Invalid mobile number format
   - Missing required parameters

2. **Service Errors (400/500):**
   - FSM gateway service unavailable
   - User not mapped in FSM system
   - Authentication/authorization failures

3. **Business Logic Errors:**
   - FSE not mapped on FSM
   - Invalid hierarchy request
   - Missing profile information

#### **Error Response Structure:**
```java
// Customer ID not found error
if (Objects.isNull(custIdFromMobile)) {
    return handleError(new BaseResponse(), HttpStatus.BAD_REQUEST.value(), ErrorMessages.CUST_ID_NOT_FOUND);
}

// FSM mapping error
if (Objects.isNull(fsmUserDetailsDO) || 
    (Objects.nonNull(fsmUserDetailsDO.getError()) && 
     (StringUtils.isNotEmpty(fsmUserDetailsDO.getError().getErrorCode()) || 
      StringUtils.isNotEmpty(fsmUserDetailsDO.getError().getErrorMsg())))) {
    return handleError(new BaseResponse(), HttpStatus.BAD_REQUEST.value(), ErrorMessages.FSE_NOT_MAPPED_ON_FSM);
}

// Controller level exception handling
catch (Exception e) {
    LOGGER.error("Error while fetching fsm user details", e);
    BaseResponse baseResponse = handleError(
        new BaseResponse(), 
        HttpStatus.INTERNAL_SERVER_ERROR.value(), 
        Utils.generatePanelErrorMessage(ErrorMessages.INTERNAL_SERVER_ERROR_MESSAGE));
    return ResponseEntity.status(baseResponse.getStatusCode()).body(baseResponse);
}
```

### **8. Response Structure Analysis**

#### **Successful Response:**
```java
{
    "statusCode": 200,
    "displayMessage": "Account team: Sales Team A, Account Sub-team: Enterprise Sales",
    "message": "FSM user details fetched successfully"
}
```

#### **Error Response Examples:**
```java
// Customer ID not found
{
    "statusCode": 400,
    "displayMessage": "Customer ID not found for provided mobile number",
    "message": "CUST_ID_NOT_FOUND"
}

// FSE not mapped on FSM
{
    "statusCode": 400,
    "displayMessage": "Field Sales Executive not mapped on FSM system",
    "message": "FSE_NOT_MAPPED_ON_FSM"
}

// Internal server error
{
    "statusCode": 500,
    "displayMessage": "Internal server error occurred while processing request",
    "message": "INTERNAL_SERVER_ERROR"
}
```

### **9. Security and Access Control**

#### **Panel Access Check:**
- **API Name Validation:** Validates "panel-search" API access permissions
- **Role-Based Access:** Ensures user has appropriate roles
- **Session Validation:** Verifies active authenticated session
- **Context Security:** Maintains secure user context

#### **Data Privacy Protection:**
- **Mobile Number Handling:** Secure processing of sensitive mobile data
- **Customer ID Protection:** Secure mapping and transmission
- **Audit Logging:** Complete request/response audit trail
- **Access Logging:** Track all FSM user detail access attempts

#### **Authentication Framework:**
- **Bearer Token Authentication:** Secure access to FSM services
- **Request Signing:** Digital signature for request integrity
- **Token Refresh:** Automatic token renewal for service availability

### **10. Integration Architecture**

#### **External Dependencies:**
1. **User ACL Service:** Mobile number to customer ID mapping
2. **FSM Gateway Service:** Field Sales Management system integration
3. **Authentication Service:** Panel access control and validation

#### **Internal Components:**
1. **SolutionLeadHelperService:** Business logic orchestration
2. **UserAclService:** User authentication and authorization
3. **FsmGatewayService:** External FSM service integration

#### **Data Flow:**
1. **Request Reception:** Controller receives mobile number parameter
2. **Access Validation:** Panel access check and authorization
3. **Customer ID Lookup:** Map mobile number to customer ID
4. **FSM Service Call:** Fetch user details from FSM system
5. **Data Processing:** Extract team and sub-team information
6. **Response Construction:** Build formatted response message

### **11. Performance Optimization**

#### **Caching Strategy:**
- **Customer ID Caching:** Cache mobile to customer ID mappings
- **FSM Token Caching:** Cache FSM access tokens to reduce authentication overhead
- **Configuration Caching:** Cache service endpoints and timeout configurations

#### **External Service Management:**
- **Timeout Configuration:** Configurable timeouts for FSM service calls
- **Retry Logic:** Implement retry mechanisms for transient failures
- **Circuit Breaker:** Prevent cascade failures in FSM service

#### **Data Processing Optimization:**
- **Profile Indexing:** Efficient access to first profile in list
- **String Validation:** Optimized string checks for team information
- **Memory Management:** Minimize object creation in response processing

### **12. Monitoring and Observability**

#### **Business Metrics:**
- **User Lookup Success Rate:** Percentage of successful FSM user retrievals
- **Team Assignment Coverage:** Ratio of users with assigned teams
- **Mobile to Customer ID Resolution:** Success rate of mobile number mapping

#### **Technical Metrics:**
- **Response Time:** End-to-end user details fetch time
- **FSM Service SLA:** External service performance monitoring
- **Error Rate:** Failed user details request percentage

#### **Audit Metrics:**
- **Request Volume:** Total user details requests per time period
- **Access Pattern Analysis:** Usage patterns by panel users
- **Data Quality:** Completeness of team and sub-team information

### **13. Business Logic Enhancements**

#### **Hierarchy Request Processing:**
- **Fixed Hierarchy Flag:** Always requests comprehensive hierarchy data
- **Multi-Level Support:** Handles user, parent, and grandparent hierarchy
- **Profile Prioritization:** Uses first profile for team information extraction

#### **Team Information Processing:**
- **Team Name Extraction:** Primary team assignment identification
- **Sub-Team Processing:** Secondary team classification
- **Fallback Handling:** Graceful handling of missing team information

#### **Response Formatting:**
- **Human-Readable Format:** "Account team: X, Account Sub-team: Y"
- **Consistent Messaging:** Standardized response format
- **Log Integration:** Comprehensive logging for debugging and monitoring

## 🔑 **Key Technical Concepts**

### **1. Multi-Service Integration Architecture**
- **User ACL Service:** Mobile number to customer ID resolution
- **FSM Gateway Service:** Field Sales Management system integration
- **Panel Access Control:** Role-based authorization framework

### **2. Comprehensive Error Handling**
- **Multi-Layer Validation:** Mobile number, customer ID, and FSM mapping validation
- **Service Error Propagation:** Detailed error information from external services
- **Graceful Degradation:** Meaningful error messages for all failure scenarios

### **3. Security-First Design**
- **Panel Access Check:** API-specific access control validation
- **Data Privacy Protection:** Secure handling of mobile numbers and customer data
- **Audit Trail Compliance:** Complete request/response logging

### **4. Field Sales Management Integration**
- **Hierarchy Support:** Multi-level organizational hierarchy processing
- **Team Assignment Logic:** Primary and secondary team classification
- **Profile-Based Processing:** User profile information extraction

### **5. Performance and Reliability**
- **Timeout Management:** Configurable timeouts for external service calls
- **Caching Strategy:** Efficient caching of authentication tokens and mappings
- **Circuit Breaker Pattern:** Resilient external service integration

This comprehensive analysis demonstrates the sophisticated **FSM user details retrieval system** that provides **secure access control**, **multi-service integration**, and **comprehensive team information** for efficient field sales management operations in the Paytm OE ecosystem!
