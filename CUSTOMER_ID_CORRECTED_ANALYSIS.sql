-- =====================================
-- 🔥 CUSTOMER ID CORRECTED ANALYSIS
-- Based on actual schema discovery
-- =====================================

-- 🎯 SCHEMA CORRECTIONS DISCOVERED:
-- user_info: mobile_number (not mobile_no), email (not email_id)
-- audit_trail: agent_cust_id exists (device/session tracking table)

-- =====================================
-- 🚀 STEP 1: GET OUR CUSTOMER'S USER INFO
-- =====================================

-- Get user_info for customer 1001647902
SELECT 
    cust_id,
    name,
    kyc_name,
    email,
    mobile_number,
    created_at,
    status
FROM user_info 
WHERE cust_id = 1001647902;

-- =====================================
-- 🚀 STEP 2: CUSTOMER ID RELATIONSHIP MAPPING (CORRECTED)
-- =====================================

SELECT 
    ubm.lead_id,
    ubm.cust_id as ubm_cust_id,
    ubm.creator_cust_id,
    ui.cust_id as user_info_cust_id,
    ui.name as user_name,
    ui.mobile_number,
    ui.email,
    ubmo.id as owner_id
FROM user_business_mapping ubm
LEFT JOIN user_business_mapping_owner ubmo ON ubm.id = ubmo.user_business_mapping_id
LEFT JOIN user_info ui ON ubmo.user_info_id = ui.id
WHERE ubm.lead_id IN ('2be1c08d-3f70-4a6e-877e-0d79c5ff7f2c', '3dbba4bb-9ad9-43df-ae9a-d65925f8562e')
ORDER BY ubm.lead_id;

-- =====================================
-- 🚀 STEP 3: ALL LEADS FOR CUSTOMER 1001647902
-- =====================================

SELECT 
    ubm.lead_id,
    ubm.solution_type,
    ubm.status,
    ubm.created_at,
    ubm.parent_lead_id,
    CASE 
        WHEN ubm.parent_lead_id IS NULL THEN 'ROOT'
        ELSE 'CHILD'
    END as hierarchy_level
FROM user_business_mapping ubm
WHERE ubm.creator_cust_id = 1001647902
ORDER BY ubm.created_at;

-- =====================================
-- 🚀 STEP 4: CUSTOMER ID PATTERN ANALYSIS
-- =====================================

SELECT 
    CASE 
        WHEN creator_cust_id < 1000000000 THEN 'LEGACY_ID (< 1B)'
        WHEN creator_cust_id BETWEEN 1000000000 AND 1099999999 THEN 'INTERNAL_USER (1.0B - 1.1B)'
        WHEN creator_cust_id BETWEEN 1100000000 AND 1199999999 THEN 'CUSTOMER_RANGE_1 (1.1B - 1.2B)'
        WHEN creator_cust_id >= 1200000000 THEN 'CUSTOMER_RANGE_2 (1.2B+)'
        ELSE 'OTHER'
    END as id_range,
    COUNT(*) as count,
    MIN(creator_cust_id) as min_id,
    MAX(creator_cust_id) as max_id,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM user_business_mapping WHERE creator_cust_id IS NOT NULL), 2) as percentage
FROM user_business_mapping 
WHERE creator_cust_id IS NOT NULL
GROUP BY 
    CASE 
        WHEN creator_cust_id < 1000000000 THEN 'LEGACY_ID (< 1B)'
        WHEN creator_cust_id BETWEEN 1000000000 AND 1099999999 THEN 'INTERNAL_USER (1.0B - 1.1B)'
        WHEN creator_cust_id BETWEEN 1100000000 AND 1199999999 THEN 'CUSTOMER_RANGE_1 (1.1B - 1.2B)'
        WHEN creator_cust_id >= 1200000000 THEN 'CUSTOMER_RANGE_2 (1.2B+)'
        ELSE 'OTHER'
    END
ORDER BY min_id;

-- =====================================
-- 🚀 STEP 5: AUDIT TRAIL AGENT ANALYSIS
-- =====================================

-- Check if customer 1001647902 appears as an agent in audit_trail
SELECT 
    agent_cust_id,
    channel,
    agent_type,
    agent_name,
    COUNT(*) as session_count,
    MIN(created_at) as first_session,
    MAX(created_at) as latest_session
FROM audit_trail 
WHERE agent_cust_id = '1001647902'
GROUP BY agent_cust_id, channel, agent_type, agent_name
ORDER BY session_count DESC;

-- =====================================
-- 🚀 STEP 6: TOP CUSTOMERS BY LEAD COUNT
-- =====================================

SELECT 
    creator_cust_id,
    COUNT(*) as total_leads,
    COUNT(DISTINCT solution_type) as solution_types_used,
    COUNT(DISTINCT CASE WHEN parent_lead_id IS NULL THEN lead_id END) as root_leads,
    COUNT(DISTINCT CASE WHEN parent_lead_id IS NOT NULL THEN lead_id END) as child_leads,
    MIN(created_at) as first_lead_created,
    MAX(created_at) as latest_lead_created
FROM user_business_mapping 
WHERE creator_cust_id IS NOT NULL
GROUP BY creator_cust_id
ORDER BY total_leads DESC
LIMIT 15;

-- =====================================
-- 🚀 STEP 7: COMPLETE LEAD HIERARCHY FOR CUSTOMER 1001647902
-- =====================================

WITH RECURSIVE lead_hierarchy AS (
    -- Root leads (no parent)
    SELECT 
        lead_id,
        parent_lead_id,
        solution_type,
        creator_cust_id,
        created_at,
        0 as level,
        CAST(solution_type AS CHAR(500)) as path
    FROM user_business_mapping 
    WHERE creator_cust_id = 1001647902 
    AND parent_lead_id IS NULL
    
    UNION ALL
    
    -- Child leads
    SELECT 
        ubm.lead_id,
        ubm.parent_lead_id,
        ubm.solution_type,
        ubm.creator_cust_id,
        ubm.created_at,
        lh.level + 1,
        CONCAT(lh.path, ' -> ', ubm.solution_type)
    FROM user_business_mapping ubm
    JOIN lead_hierarchy lh ON ubm.parent_lead_id = lh.lead_id
    WHERE ubm.creator_cust_id = 1001647902
)
SELECT 
    level,
    lead_id,
    solution_type,
    created_at,
    path as hierarchy_path
FROM lead_hierarchy 
ORDER BY level, created_at;

-- =====================================
-- 🚀 STEP 8: USER_INFO RELATIONSHIPS
-- =====================================

-- Check how user_info relates to our customer's leads
SELECT 
    ui.id as user_info_id,
    ui.cust_id,
    ui.name,
    ui.email,
    ui.mobile_number,
    ui.created_at,
    ubm.lead_id,
    ubm.solution_type
FROM user_info ui
JOIN user_business_mapping_owner ubmo ON ui.id = ubmo.user_info_id
JOIN user_business_mapping ubm ON ubmo.user_business_mapping_id = ubm.id
WHERE ubm.creator_cust_id = 1001647902
ORDER BY ui.created_at;

-- =====================================
-- 🚀 STEP 9: CUSTOMER ID NULL ANALYSIS
-- =====================================

SELECT 
    'user_business_mapping.cust_id' as field_type,
    COUNT(CASE WHEN cust_id IS NOT NULL THEN 1 END) as not_null_count,
    COUNT(CASE WHEN cust_id IS NULL THEN 1 END) as null_count,
    COUNT(*) as total_count,
    ROUND(COUNT(CASE WHEN cust_id IS NULL THEN 1 END) * 100.0 / COUNT(*), 2) as null_percentage
FROM user_business_mapping

UNION ALL

SELECT 
    'user_business_mapping.creator_cust_id' as field_type,
    COUNT(CASE WHEN creator_cust_id IS NOT NULL THEN 1 END) as not_null_count,
    COUNT(CASE WHEN creator_cust_id IS NULL THEN 1 END) as null_count,
    COUNT(*) as total_count,
    ROUND(COUNT(CASE WHEN creator_cust_id IS NULL THEN 1 END) * 100.0 / COUNT(*), 2) as null_percentage
FROM user_business_mapping

UNION ALL

SELECT 
    'user_info.cust_id' as field_type,
    COUNT(CASE WHEN cust_id IS NOT NULL THEN 1 END) as not_null_count,
    COUNT(CASE WHEN cust_id IS NULL THEN 1 END) as null_count,
    COUNT(*) as total_count,
    ROUND(COUNT(CASE WHEN cust_id IS NULL THEN 1 END) * 100.0 / COUNT(*), 2) as null_percentage
FROM user_info;

-- =====================================
-- 🚀 STEP 10: AGENT VS CUSTOMER VERIFICATION
-- =====================================

-- Check if customer 1001647902 appears in agent-related tables
SELECT 'agent_creation_request' as table_name, COUNT(*) as count
FROM agent_creation_request WHERE cust_id = '1001647902'

UNION ALL

SELECT 'agent_group.creator_cust_id' as table_name, COUNT(*) as count  
FROM agent_group WHERE creator_cust_id = 1001647902

UNION ALL

SELECT 'service_agent_mapping.service_agent_cust_id' as table_name, COUNT(*) as count
FROM service_agent_mapping WHERE service_agent_cust_id = 1001647902

UNION ALL

SELECT 'audit_trail.agent_cust_id' as table_name, COUNT(*) as count
FROM audit_trail WHERE agent_cust_id = '1001647902';

-- =====================================
-- 🎯 CRITICAL INSIGHTS TO DISCOVER:
-- =====================================

-- 1. Is customer 1001647902 in user_info table?
-- 2. What's the complete lead hierarchy for this customer?
-- 3. Does this customer appear as an agent in audit_trail?
-- 4. What customer ID ranges exist and what do they represent?
-- 5. Why are most cust_id fields NULL in user_business_mapping?
-- 6. How do creator_cust_id and user_info.cust_id relate?
