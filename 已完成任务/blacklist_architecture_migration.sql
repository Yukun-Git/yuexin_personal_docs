-- Copyright(c) 2025
-- All rights reserved.
--
-- Author: yukun.xing <xingyukun@gmail.com>
-- Date:   2025/01/12
--
-- Blacklist Architecture Migration Script
-- 
-- ⚠️  WARNING: This script will DROP existing blacklist tables and data
-- Please backup your database before executing this script
--
-- Usage:
-- psql -h localhost -p 8668 -U yuexin -d pigeon_sms -f blacklist_architecture_migration.sql

-- Connect to database
\c pigeon_sms;

-- ============================================================================
-- STEP 1: Drop existing blacklist tables and related objects
-- ============================================================================

-- Drop triggers first
DROP TRIGGER IF EXISTS update_blacklist_entries_updated_at ON blacklist_entries;
DROP TRIGGER IF EXISTS update_blacklist_sources_updated_at ON blacklist_sources;
DROP TRIGGER IF EXISTS update_blacklist_types_updated_at ON blacklist_types;
DROP TRIGGER IF EXISTS update_intercept_logs_updated_at ON intercept_logs;

-- Drop existing tables (CASCADE to handle foreign key dependencies)
DROP TABLE IF EXISTS intercept_logs CASCADE;
DROP TABLE IF EXISTS blacklist_entries CASCADE;
DROP TABLE IF EXISTS blacklist_sources CASCADE;
DROP TABLE IF EXISTS blacklist_types CASCADE;

-- Drop existing enum types
DROP TYPE IF EXISTS blacklist_status CASCADE;
DROP TYPE IF EXISTS blacklist_severity CASCADE;
DROP TYPE IF EXISTS blacklist_type_category CASCADE;
DROP TYPE IF EXISTS blacklist_source_type CASCADE;
DROP TYPE IF EXISTS intercept_action CASCADE;

-- ============================================================================
-- STEP 2: Create new enum types
-- ============================================================================

-- Blacklist status enum (simplified)
CREATE TYPE blacklist_status_enum AS ENUM ('ACTIVE', 'INACTIVE');

-- Blacklist source enum (simplified)
CREATE TYPE blacklist_source_enum AS ENUM ('MANUAL', 'SYSTEM', 'COMPLAINT', 'THIRD_PARTY', 'API', 'BULK_IMPORT');

-- ============================================================================
-- STEP 3: Create new table structure
-- ============================================================================

-- 1. 黑名单主表 (专注手机号集合管理)
CREATE TABLE blacklists (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- 基本信息
    name VARCHAR(200) NOT NULL UNIQUE,               -- "垃圾电话黑名单" (全局唯一)
    description TEXT,                                -- 黑名单描述
    
    -- 状态管理  
    status blacklist_status_enum DEFAULT 'ACTIVE',  -- ACTIVE/INACTIVE
    
    -- 统计信息 (冗余字段，便于查询)
    phone_count INTEGER DEFAULT 0,                  -- 包含的手机号数量
    intercept_count INTEGER DEFAULT 0,              -- 总拦截次数
    last_match_at TIMESTAMP,                        -- 最后匹配时间
    
    -- 元数据
    created_by INTEGER REFERENCES admin_users(id),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    source_enum blacklist_source_enum DEFAULT 'MANUAL',
    notes TEXT,
    tags TEXT[],                                     -- 标签便于分类和筛选
    
    CONSTRAINT check_phone_count_non_negative CHECK (phone_count >= 0),
    CONSTRAINT check_intercept_count_non_negative CHECK (intercept_count >= 0)
);

-- 2. 手机号条目表 (简化)
CREATE TABLE blacklist_phone_entries (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- 关联黑名单
    blacklist_id UUID NOT NULL REFERENCES blacklists(id) ON DELETE CASCADE,
    
    -- 手机号信息
    phone_number VARCHAR(20) NOT NULL,              -- 原始手机号
    normalized_phone VARCHAR(20) NOT NULL,          -- 标准化后的号码 (便于匹配)
    
    -- 条目状态
    status blacklist_status_enum DEFAULT 'ACTIVE',
    
    -- 匹配规则
    is_regex BOOLEAN DEFAULT FALSE,                 -- 支持正则匹配
    
    -- 统计
    match_count INTEGER DEFAULT 0,
    last_match_at TIMESTAMP,
    
    -- 元数据  
    notes TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    imported_from VARCHAR(100),                     -- 批量导入来源标记
    
    -- 约束
    UNIQUE(blacklist_id, normalized_phone),         -- 同黑名单内号码唯一
    CHECK (phone_number ~ '^[0-9+\-\s\(\)]{7,20}$'), -- 手机号格式检查
    CONSTRAINT check_match_count_non_negative CHECK (match_count >= 0)
);

-- 3. 拦截日志表 (简化)
CREATE TABLE blacklist_intercept_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- 关联信息
    blacklist_id UUID NOT NULL REFERENCES blacklists(id),
    matched_phone_entry_id UUID REFERENCES blacklist_phone_entries(id),
    
    -- 拦截内容
    intercepted_phone VARCHAR(20) NOT NULL,         -- 被拦截的手机号
    
    -- 拦截上下文
    source_ip INET,                                 -- 来源IP
    user_agent TEXT,                               -- User Agent
    request_id VARCHAR(100),                       -- 请求ID
    
    -- 时间和性能
    created_at TIMESTAMP DEFAULT NOW(),
    processing_time_ms INTEGER,                    -- 处理耗时(毫秒)
    
    CONSTRAINT check_processing_time_non_negative CHECK (processing_time_ms IS NULL OR processing_time_ms >= 0)
);

-- ============================================================================
-- STEP 4: Create indexes
-- ============================================================================

-- 黑名单表索引
CREATE INDEX idx_blacklists_name ON blacklists (name);
CREATE INDEX idx_blacklists_status ON blacklists (status);
CREATE INDEX idx_blacklists_updated_at ON blacklists (updated_at DESC);
CREATE INDEX idx_blacklists_created_by ON blacklists (created_by);
CREATE INDEX idx_blacklists_source ON blacklists (source_enum);
CREATE INDEX idx_blacklists_tags ON blacklists USING GIN (tags);

-- 手机号条目表索引  
CREATE INDEX idx_phone_entries_blacklist ON blacklist_phone_entries (blacklist_id);
CREATE INDEX idx_phone_entries_phone_active ON blacklist_phone_entries (normalized_phone) WHERE status = 'ACTIVE';
CREATE INDEX idx_phone_entries_blacklist_status ON blacklist_phone_entries (blacklist_id, status);
CREATE INDEX idx_phone_entries_phone_number ON blacklist_phone_entries (phone_number);
CREATE INDEX idx_phone_entries_normalized_phone ON blacklist_phone_entries (normalized_phone);
CREATE INDEX idx_phone_entries_created_at ON blacklist_phone_entries (created_at DESC);
CREATE INDEX idx_phone_entries_match_count ON blacklist_phone_entries (match_count DESC);

-- 拦截日志表索引
CREATE INDEX idx_intercept_logs_blacklist_time ON blacklist_intercept_logs (blacklist_id, created_at);
CREATE INDEX idx_intercept_logs_phone_time ON blacklist_intercept_logs (intercepted_phone, created_at);
CREATE INDEX idx_intercept_logs_phone_entry ON blacklist_intercept_logs (matched_phone_entry_id);
CREATE INDEX idx_intercept_logs_source_ip ON blacklist_intercept_logs (source_ip, created_at);
CREATE INDEX idx_intercept_logs_request_id ON blacklist_intercept_logs (request_id);

-- ============================================================================
-- STEP 5: Create triggers for automatic statistics updates
-- ============================================================================

-- 更新黑名单统计信息的函数
CREATE OR REPLACE FUNCTION update_blacklist_statistics()
RETURNS TRIGGER AS $$
BEGIN
    -- 更新手机号数量统计
    IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' OR TG_OP = 'DELETE' THEN
        UPDATE blacklists 
        SET phone_count = (
            SELECT COUNT(*) 
            FROM blacklist_phone_entries 
            WHERE blacklist_id = COALESCE(NEW.blacklist_id, OLD.blacklist_id)
            AND status = 'ACTIVE'
        ),
        updated_at = NOW()
        WHERE id = COALESCE(NEW.blacklist_id, OLD.blacklist_id);
    END IF;
    
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- 创建触发器
CREATE TRIGGER trigger_update_blacklist_statistics
    AFTER INSERT OR UPDATE OR DELETE ON blacklist_phone_entries
    FOR EACH ROW EXECUTE FUNCTION update_blacklist_statistics();

-- 更新拦截统计信息的函数
CREATE OR REPLACE FUNCTION update_intercept_statistics()
RETURNS TRIGGER AS $$
BEGIN
    -- 更新黑名单拦截统计
    UPDATE blacklists 
    SET intercept_count = intercept_count + 1,
        last_match_at = NOW(),
        updated_at = NOW()
    WHERE id = NEW.blacklist_id;
    
    -- 更新手机号条目匹配统计
    IF NEW.matched_phone_entry_id IS NOT NULL THEN
        UPDATE blacklist_phone_entries
        SET match_count = match_count + 1,
            last_match_at = NOW()
        WHERE id = NEW.matched_phone_entry_id;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 创建触发器
CREATE TRIGGER trigger_update_intercept_statistics
    AFTER INSERT ON blacklist_intercept_logs
    FOR EACH ROW EXECUTE FUNCTION update_intercept_statistics();

-- ============================================================================
-- STEP 6: Insert default data
-- ============================================================================

-- Insert default blacklist collections
INSERT INTO blacklists (id, name, description, status, source_enum, tags, notes) VALUES
('c29c210d-fa35-4af0-b566-ad4576801173', '默认手机号黑名单', '系统默认创建的手机号黑名单，用于拦截垃圾电话和恶意号码', 'ACTIVE', 'SYSTEM', ARRAY['默认', '系统'], '系统初始化时创建的默认黑名单'),
('38a3d3b9-5147-4e5e-9ee7-01a0762372d5', '客户投诉黑名单', '基于客户投诉建立的手机号黑名单', 'ACTIVE', 'COMPLAINT', ARRAY['投诉', '客户反馈'], '用于管理客户投诉的手机号码'),
('f7e8b9c5-3d2a-4b8c-9e1f-234567890abc', '垃圾电话黑名单', '已识别的垃圾电话号码集合', 'ACTIVE', 'MANUAL', ARRAY['垃圾电话', '营销'], '专门用于拦截垃圾电话和营销骚扰')
ON CONFLICT (id) DO NOTHING;

-- Insert sample blacklist phone entries
INSERT INTO blacklist_phone_entries (blacklist_id, phone_number, normalized_phone, status, notes) VALUES
('c29c210d-fa35-4af0-b566-ad4576801173', '13800138000', '8613800138000', 'ACTIVE', '系统测试号码'),
('c29c210d-fa35-4af0-b566-ad4576801173', '13900139000', '8613900139000', 'ACTIVE', '系统测试号码'),
('38a3d3b9-5147-4e5e-9ee7-01a0762372d5', '18612345678', '8618612345678', 'ACTIVE', '客户投诉号码示例'),
('f7e8b9c5-3d2a-4b8c-9e1f-234567890abc', '17711110000', '8617711110000', 'ACTIVE', '垃圾电话示例')
ON CONFLICT (blacklist_id, normalized_phone) DO NOTHING;

-- ============================================================================
-- STEP 7: Verification
-- ============================================================================

-- Verify table creation
\d blacklists
\d blacklist_phone_entries
\d blacklist_intercept_logs

-- Verify data insertion
SELECT 
    b.name,
    b.status,
    b.phone_count,
    COUNT(p.id) as actual_phone_count
FROM blacklists b
LEFT JOIN blacklist_phone_entries p ON b.id = p.blacklist_id AND p.status = 'ACTIVE'
GROUP BY b.id, b.name, b.status, b.phone_count
ORDER BY b.name;

-- Verify enum types
SELECT enumlabel FROM pg_enum WHERE enumtypid = 'blacklist_status_enum'::regtype ORDER BY enumsortorder;
SELECT enumlabel FROM pg_enum WHERE enumtypid = 'blacklist_source_enum'::regtype ORDER BY enumsortorder;

-- ============================================================================
-- Migration Complete
-- ============================================================================

\echo '========================================='
\echo 'Blacklist Architecture Migration Complete'
\echo '========================================='
\echo 'New tables created:'
\echo '  - blacklists (main table for phone number collections)'
\echo '  - blacklist_phone_entries (simplified phone entries)'
\echo '  - blacklist_intercept_logs (simplified intercept logs)'
\echo ''
\echo 'Default data inserted:'
\echo '  - 3 default blacklist collections'
\echo '  - 4 sample phone entries'
\echo ''
\echo 'Please verify the data integrity above.'
\echo '========================================='