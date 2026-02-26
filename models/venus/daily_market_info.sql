{{ config(
    alias = 'daily_market_info'
    , materialized = 'incremental'
    , incremental_strategy = 'delete+insert'
    , unique_key = ['day']
    , properties = {
        "partitioned_by": "ARRAY['day']"
    }
)
}}

WITH markets AS (
    SELECT m.*
    FROM dune.xvslove_team.dataset_markets_all_chains m
    WHERE vToken != 'VAI'
),

exchange_rates AS (
    SELECT
        *,
        LEAD(day) OVER (PARTITION BY chain, contract_address ORDER BY day) AS next_update_day
    FROM (
        SELECT chain, contract_address, call_block_date AS day, AVG(output_0) AS exchange_rate_raw
        FROM (
            SELECT 'bnb' AS chain, contract_address, call_block_date, output_0 FROM venus_bnb.vbnb_v2_call_exchangeratestored WHERE call_success
            UNION ALL
            SELECT 'bnb' AS chain, contract_address, call_block_date, output_0 FROM venus_bnb.vbep20_bnb_core_call_exchangeratestored WHERE call_success
            UNION ALL
            SELECT 'bnb' AS chain, contract_address, call_block_date, output_0 FROM venus_bnb.vbep20delegate_v2_call_exchangeratestored WHERE call_success AND contract_address IN (0x0c1da220d301155b87318b90692da8dc43b67340, 0xcc1db43a06d97f736c7b045aedd03c6707c09bdf) --two contracts that could not be carried over to the new table
            UNION ALL
            SELECT chain, contract_address, call_block_date, output_0 FROM venus_multichain.VToken_call_exchangeRateStored WHERE call_success
    )
        GROUP BY 1,2,3
    )
),

reserve_factor AS ( --reserve factor changes over time
    SELECT
        *,
        LEAD(day) OVER (PARTITION BY chain, contract_address ORDER BY day) AS next_update_day
    FROM (
        SELECT chain, contract_address, evt_block_date AS day, AVG(newReserveFactorMantissa / POWER(10, 18)) AS reserve_factor
        FROM (
            SELECT 'bnb' AS chain, evt_block_date, contract_address, newReserveFactorMantissa FROM venus_bnb.vbnb_v2_evt_newreservefactor
            UNION ALL
            SELECT 'bnb' AS chain, evt_block_date, contract_address, newReserveFactorMantissa FROM venus_bnb.vbep20_bnb_core_evt_newreservefactor
            UNION ALL
            SELECT 'bnb' AS chain, evt_block_date, contract_address, newReserveFactorMantissa FROM venus_bnb.vbep20delegate_v2_evt_newreservefactor WHERE contract_address IN (0x0c1da220d301155b87318b90692da8dc43b67340, 0xcc1db43a06d97f736c7b045aedd03c6707c09bdf) --two contracts that could not be carried over to the new table
            UNION ALL
            SELECT chain, evt_block_date, contract_address, newReserveFactorMantissa FROM venus_multichain.VToken_evt_NewReserveFactor
        )
        GROUP BY 1,2,3
    )
),

comptroller AS ( -- used to get share of protocol liquidation fee
    SELECT
        *,
        LEAD(day) OVER (PARTITION BY chain, contract_address ORDER BY day) AS next_update_day
    FROM (
        SELECT 'bnb' AS chain, contract_address, evt_block_date AS day, newComptroller AS comptroller, ROW_NUMBER() OVER(PARTITION BY contract_address ORDER BY evt_block_time DESC, evt_index DESC) AS rn FROM venus_bnb.vbnb_v2_evt_newcomptroller
        UNION ALL
        SELECT 'bnb' AS chain, contract_address, evt_block_date AS day, newComptroller AS comptroller, ROW_NUMBER() OVER(PARTITION BY contract_address ORDER BY evt_block_time DESC, evt_index DESC) AS rn FROM venus_bnb.vbep20_bnb_core_evt_newcomptroller
        UNION ALL
        SELECT 'bnb' AS chain, contract_address, evt_block_date AS day, newComptroller AS comptroller, ROW_NUMBER() OVER(PARTITION BY contract_address ORDER BY evt_block_time DESC, evt_index DESC) AS rn FROM venus_bnb.vbep20delegate_v2_evt_newcomptroller WHERE contract_address IN (0x0c1da220d301155b87318b90692da8dc43b67340, 0xcc1db43a06d97f736c7b045aedd03c6707c09bdf) --two contracts that could not be carried over to the new table
        UNION ALL
        SELECT chain, contract_address, evt_block_date AS day, newComptroller AS comptroller, ROW_NUMBER() OVER(PARTITION BY contract_address ORDER BY evt_block_time DESC, evt_index DESC) AS rn FROM venus_multichain.vtoken_evt_newcomptroller
    )
    WHERE rn = 1
),

liquidation_mantissa AS ( --total liquidation fee (including liquidator share) - used to derive protocol liquidation fee for markets not emitting newprotocolseizeshare event
    --on BNB core pool, set by market and e-mode group (for now, only showing liquidation fee for non-emode)
    --on other chains, set for the entire pool
    SELECT DISTINCT
        day, contract_address AS comptroller, vtoken_address, liquidation_mantissa,
        CASE
            WHEN vtoken_address IS NULL THEN LEAD(day) OVER(PARTITION BY contract_address ORDER BY day)
            ELSE LEAD(day) OVER(PARTITION BY contract_address, vtoken_address ORDER BY day)
        END AS next_update_day
    FROM (
        SELECT evt_block_date AS day, contract_address, vtoken AS vtoken_address, AVG(newLiquidationIncentiveMantissa / POWER(10,18)) AS liquidation_mantissa FROM venus_bnb.comptroller_evt_newliquidationincentive WHERE poolId = 0 OR poolId IS NULL GROUP BY 1,2,3
        UNION ALL
        SELECT evt_block_date AS day, contract_address, NULL AS vtoken_address, AVG(newLiquidationIncentiveMantissa / POWER(10,18)) AS liquidation_mantissa FROM venus_multichain.comptroller_evt_newliquidationincentive WHERE chain != 'bnb' GROUP BY 1,2,3
        UNION ALL
        SELECT evt_block_date AS day, contract_address, NULL AS vtoken_address, AVG(newLiquidationIncentiveMantissa / POWER(10,18)) AS liquidation_mantissa FROM venus_ethereum.comptroller_core_evt_newliquidationincentive GROUP BY 1,2,3
        UNION ALL
        SELECT evt_block_date AS day, contract_address, NULL AS vtoken_address, AVG(newLiquidationIncentiveMantissa / POWER(10,18)) AS liquidation_mantissa FROM venus_ethereum.comptroller_curve_evt_newliquidationincentive GROUP BY 1,2,3
        UNION ALL
        SELECT evt_block_date AS day, contract_address, NULL AS vtoken_address, AVG(newLiquidationIncentiveMantissa / POWER(10,18)) AS liquidation_mantissa FROM venus_bnb.comptroller_defi_pool_evt_newliquidationincentive GROUP BY 1,2,3
        UNION ALL
        SELECT evt_block_date AS day, contract_address, NULL AS vtoken_address, AVG(newLiquidationIncentiveMantissa / POWER(10,18)) AS liquidation_mantissa FROM venus_bnb.comptroller_gamefi_pool_evt_newliquidationincentive GROUP BY 1,2,3
        UNION ALL
        SELECT evt_block_date AS day, contract_address, NULL AS vtoken_address, AVG(newLiquidationIncentiveMantissa / POWER(10,18)) AS liquidation_mantissa FROM venus_bnb.comptroller_liquidstakebnb_pool_evt_newliquidationincentive GROUP BY 1,2,3
        UNION ALL
        SELECT evt_block_date AS day, contract_address, NULL AS vtoken_address, AVG(newLiquidationIncentiveMantissa / POWER(10,18)) AS liquidation_mantissa FROM venus_bnb.comptroller_stablecoin_pool_evt_newliquidationincentive GROUP BY 1,2,3
        UNION ALL
        SELECT evt_block_date AS day, contract_address, NULL AS vtoken_address, AVG(newLiquidationIncentiveMantissa / POWER(10,18)) AS liquidation_mantissa FROM venus_bnb.comptroller_tron_pool_evt_newliquidationincentive GROUP BY 1,2,3
    )
),

liquidation_seize_share AS ( --share of protocol liquidation fee
    SELECT
        *,
        LEAD(day) OVER (PARTITION BY chain, contract_address ORDER BY day) AS next_update_day
    FROM (
        SELECT chain, contract_address, evt_block_date AS day, MAX(newProtocolSeizeShareMantissa / POWER(10,18)) AS liquidation_seize_share --need max because on zksync there's always two events: one with new mantissa set to 0 followed by one with mantissa set to new value
        FROM venus_multichain.vtoken_evt_newprotocolseizeshare
        GROUP BY 1,2,3
    )
)

SELECT
    m.blockchain,
    CASE WHEN m.blockchain = 'base' AND m.pool IS NULL THEN 'core' ELSE LOWER(m.pool) END AS pool,
    m.vToken AS vToken,
    m.vToken_contract_address AS vToken_address,
    m.vToken_decimals,
    m.symbol AS underlying_token,
    m.underlying_token_address,
    m.decimals AS underlying_token_decimals,
    m.deployment_date,
    COALESCE(p1.day, p2.timestamp) AS day,
    COALESCE(p1.price, p2.price) AS price,
    e.exchange_rate_raw / POWER(10, m.decimals + 10) AS exchange_rate,
    r.reserve_factor,
    COALESCE(
        l.liquidation_seize_share, --works for most vTokens
        ROUND((lm.liquidation_mantissa - 1)/2, 6) --for others assume 50% of total liquidation fee
        ,0 --if don't have seize share or total liquidation fee, assume 0
    ) AS liquidation_seize_share,
    c.comptroller,
    lm.liquidation_mantissa
FROM markets m
    LEFT JOIN (
        SELECT *, CAST(timestamp AS DATE) AS day
        FROM prices.day
        {% if is_incremental() %}WHERE timestamp >= date_add('day', -3, current_date){% endif %}
    ) p1 ON p1.day >= date(m.deployment_date) AND (
            --filling in for missing prices
            (p1.blockchain = m.blockchain AND p1.contract_address = m.underlying_token_address)
            OR (m.symbol = 'wUSDM' AND p1.blockchain = 'arbitrum' AND p1.contract_address = 0x57f5e098cad7a3d1eed53991d4d66c45c9af7812) --taking arb wUSDM price for zksync wUSDM
            OR (m.symbol IN ('xSolvBTC', 'solvBTC') AND p1.blockchain IS NULL AND p1.symbol = 'BTC')
            OR (m.symbol IN ('zkETH', 'wsuperOETHb') AND p1.blockchain IS NULL AND p1.symbol = 'ETH')
            OR (m.symbol IN ('weETH') AND m.blockchain = 'bnb' AND p1.blockchain = 'ethereum' AND p1.contract_address = 0xcd5fe23c85820f7b72d0926fc9b05b43e359b7ee)
            OR (m.symbol IN ('weETHs') AND p1.blockchain = 'ethereum' AND p1.contract_address = 0xcd5fe23c85820f7b72d0926fc9b05b43e359b7ee) --for weETHs using approximation to weETH
            OR (m.symbol = 'WBTC' AND m.blockchain = 'unichain' AND p1.blockchain = 'unichain' AND p1.contract_address = 0x927b51f251480a681271180da4de28d44ec4afb8)
            OR (m.symbol IN ('TUSDOLD', 'sFRAX') AND p1.blockchain = 'ethereum' AND p1.contract_address = 0x0000000000085d4780b73119b644ae5ecd22b376) -- for sFRAX using approximation as stablecoin
            OR (m.symbol IN ('FDUSD') AND m.blockchain = 'opbnb' AND p1.blockchain = 'bnb' AND p1.contract_address = 0xc5f0f7b66764f6ec8c8dff7ba683102295e16409)
            OR (m.symbol = 'TRXOLD' AND p1.blockchain = 'bnb' AND p1.contract_address = 0xce7de646e7208a4ef112cb6ed5038fa6cc6b12e3)
            OR (m.symbol = 'NFT' AND p1.blockchain = 'bnb' AND p1.contract_address = 0xfaab744db9def8e13194600ed02bc5d5bed3b85c)
            OR (m.symbol = 'BTCB' AND p1.blockchain = 'bnb' AND p1.contract_address = 0x7130d2a12b9bcbfae4f2634d864a1ee1ce3ead9c)
            OR (m.symbol = 'eBTC' AND p1.blockchain = 'arbitrum' AND p1.contract_address = 0x657e8c867d8b37dcc18fa4caead9c45eb088c642)
            OR (m.symbol IN ('asBNB', 'stkBNB') AND p1.blockchain = 'bnb' AND p1.contract_address = 0xbb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c) --approximation with BNB, doesn't account for yield
            OR (m.symbol = 'sfrxETH' AND p1.blockchain = 'ethereum' AND p1.contract_address = 0x5e8422345238f34275888049021821e8e08caa1f) --approximation with frxETH, doesn't account for yield
            OR (m.symbol = 'U' AND p1.blockchain = 'bnb' AND p1.contract_address = 0x55d398326f99059fF775485246999027B3197955) --approximation with USTC, doesn't account for yield
    )
    LEFT JOIN (SELECT * FROM query_5204403) p2 ON -- pt-token prices
        p2.timestamp < CURRENT_DATE AND p2.timestamp >= date(m.deployment_date)
        AND p2.contract_address = m.underlying_token_address
        AND p2.contract_address != 0x541b5eeac7d4434c8f87e2d32019d67611179606 --issue in the pricing
    LEFT JOIN exchange_rates e ON m.vToken_contract_address = e.contract_address AND m.blockchain = e.chain AND COALESCE(p1.day, p2.timestamp) >= e.day AND (COALESCE(p1.day, p2.timestamp) < e.next_update_day OR e.next_update_day IS NULL)
    LEFT JOIN reserve_factor r ON m.vToken_contract_address = r.contract_address AND m.blockchain = r.chain AND COALESCE(p1.day, p2.timestamp) >= r.day AND (COALESCE(p1.day, p2.timestamp) < r.next_update_day OR r.next_update_day IS NULL)
    LEFT JOIN comptroller c ON m.vToken_contract_address = c.contract_address AND m.blockchain = c.chain AND COALESCE(p1.day, p2.timestamp) >= c.day AND (COALESCE(p1.day, p2.timestamp) < c.next_update_day OR c.next_update_day IS NULL)
    LEFT JOIN liquidation_mantissa lm ON
        (((m.blockchain != 'bnb' OR m.pool != 'Core' OR lm.vtoken_address IS NULL) AND c.comptroller = lm.comptroller)
        OR (m.blockchain = 'bnb' AND m.pool = 'Core' AND m.vToken_contract_address = lm.vtoken_address))
        AND COALESCE(p1.day, p2.timestamp) >= lm.day AND (COALESCE(p1.day, p2.timestamp) < lm.next_update_day OR lm.next_update_day IS NULL)
    LEFT JOIN liquidation_seize_share l ON m.vToken_contract_address = l.contract_address AND m.blockchain = l.chain AND COALESCE(p1.day, p2.timestamp) >= l.day AND (COALESCE(p1.day, p2.timestamp) < l.next_update_day OR l.next_update_day IS NULL)
{% if is_incremental() %}
WHERE COALESCE(p1.day, p2.timestamp) >= date_add('day', -2, current_date)
{% endif %}
