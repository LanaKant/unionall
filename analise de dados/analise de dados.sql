-- ANÁLISE DE DADOS - TURMA 6
-- Autor: Hilana Cavalcanti
-- Ferramenta: DuckDB
-- Fontes de dados: datatran2023.csv, datatran2024.csv, datatran2025.csv
-- Objetivo: ingerir, integrar, limpar, enriquecer e analisar os
-- acidentes da Polícia Rodoviária Federal de 2023 a 2025.

-- PARTE 1 - INGESTÃO E INTEGRAÇÃO

-- Importação dos três arquivos CSV e consolidação em uma única tabela.
CREATE OR REPLACE TABLE acidentes_prf_historico AS

SELECT *
FROM read_csv(
    'C:/Users/NATI PROAD/Downloads/analise de dados-20260924T153007Z-1-001/analise de dados/datatran2023/datatran2023.csv',
    delim = ';',
    header = true,
    encoding = 'latin-1'
)

UNION ALL

SELECT *
FROM read_csv(
    'C:/Users/NATI PROAD/Downloads/analise de dados-20260924T153007Z-1-001/analise de dados/datatran2024/datatran2024.csv',
    delim = ';',
    header = true,
    encoding = 'latin-1'
)

UNION ALL

SELECT *
FROM read_csv(
    'C:/Users/NATI PROAD/Downloads/analise de dados-20260924T153007Z-1-001/analise de dados/datatran2025/datatran2025.csv',
    delim = ';',
    header = true,
    encoding = 'latin-1'
);

-- PARTE 2 - LIMPEZA E SELEÇÃO DE COLUNAS
-- Remove as colunas administrativas que não serão
-- utilizadas na análise descritiva.
CREATE OR REPLACE VIEW vw_acidentes_limpa AS
SELECT
    * EXCLUDE (latitude, longitude, regional, delegacia, uop)
FROM acidentes_prf_historico;

-- PARTE 3 - ENGENHARIA DE RECURSOS
-- Cria variáveis derivadas para facilitar as análises temporais,
-- de severidade, fim de semana e períodos comemorativos.
CREATE OR REPLACE VIEW vw_acidentes_enriquecida AS
SELECT
    v.*,

    -- Variável-alvo binária: 1 para acidente com pelo menos uma morte.
    CASE
        WHEN mortos >= 1 THEN 1
        ELSE 0
    END AS acidente_fatal,

    -- Ano e mês extraídos da data do acidente.
    EXTRACT(YEAR FROM TRY_CAST(data_inversa AS DATE))::INTEGER AS ano_acidente,
    EXTRACT(MONTH FROM TRY_CAST(data_inversa AS DATE))::INTEGER AS mes_acidente,

    -- 1 para sábado/domingo e 0 para os demais dias.
    CASE
        WHEN LOWER(TRIM(dia_semana)) IN ('sábado', 'sabado', 'domingo') THEN 1
        ELSE 0
    END AS fim_de_semana,

    -- Períodos comemorativos:
    -- Fim de Ano: 20/12 a 31/12 ou 01/01 a 02/01.
    -- Carnaval: aproximação pelos principais dias de Carnaval de cada ano.
    -- Demais datas: Normal.
    CASE
        WHEN (
            (EXTRACT(MONTH FROM TRY_CAST(data_inversa AS DATE)) = 12
             AND EXTRACT(DAY FROM TRY_CAST(data_inversa AS DATE)) >= 20)
            OR
            (EXTRACT(MONTH FROM TRY_CAST(data_inversa AS DATE)) = 1
             AND EXTRACT(DAY FROM TRY_CAST(data_inversa AS DATE)) <= 2)
        )
        THEN 'Fim de Ano'

        WHEN TRY_CAST(data_inversa AS DATE) BETWEEN DATE '2023-02-20' AND DATE '2023-02-21'
        THEN 'Carnaval'

        WHEN TRY_CAST(data_inversa AS DATE) BETWEEN DATE '2024-02-12' AND DATE '2024-02-13'
        THEN 'Carnaval'

        WHEN TRY_CAST(data_inversa AS DATE) BETWEEN DATE '2025-03-03' AND DATE '2025-03-04'
        THEN 'Carnaval'

        ELSE 'Normal'
    END AS data_comemorativa

FROM vw_acidentes_limpa v;

-- PARTE 4 - QUESTÕES DE NEGÓCIO

-- Questão 1 - Tendência anual e severidade:
-- total de acidentes, total de mortos e taxa de letalidade por ano.
SELECT
    ano_acidente AS ano,
    COUNT(*) AS total_acidentes,
    SUM(mortos) AS total_vitimas_fatais,
    ROUND(100.0 * SUM(acidente_fatal) / NULLIF(COUNT(*), 0), 2)
        AS taxa_letalidade_percentual
FROM vw_acidentes_enriquecida
GROUP BY ano_acidente
ORDER BY ano_acidente;


-- Questão 2 - Sazonalidade mensal:
-- compara o volume de acidentes e a taxa de letalidade por mês.
SELECT
    mes_acidente AS mes,
    COUNT(*) AS total_acidentes,
    SUM(mortos) AS total_vitimas_fatais,
    ROUND(100.0 * SUM(acidente_fatal) / NULLIF(COUNT(*), 0), 2)
        AS taxa_letalidade_percentual
FROM vw_acidentes_enriquecida
GROUP BY mes_acidente
ORDER BY taxa_letalidade_percentual DESC, mes;


-- Questão 3 - Influência da luminosidade:
-- compara volume e proporção de acidentes fatais por fase do dia.
SELECT
    fase_dia,
    COUNT(*) AS total_acidentes,
    SUM(mortos) AS total_vitimas_fatais,
    SUM(acidente_fatal) AS total_acidentes_fatais,
    ROUND(100.0 * SUM(acidente_fatal) / NULLIF(COUNT(*), 0), 2)
        AS taxa_letalidade_percentual
FROM vw_acidentes_enriquecida
GROUP BY fase_dia
ORDER BY taxa_letalidade_percentual DESC;


-- Questão 4 - Impacto dos finais de semana:
-- compara a taxa de letalidade entre finais de semana e dias úteis.
SELECT
    CASE
        WHEN fim_de_semana = 1 THEN 'Fim de semana'
        ELSE 'Dia útil'
    END AS periodo,
    COUNT(*) AS total_acidentes,
    SUM(mortos) AS total_vitimas_fatais,
    SUM(acidente_fatal) AS total_acidentes_fatais,
    ROUND(100.0 * SUM(acidente_fatal) / NULLIF(COUNT(*), 0), 2)
        AS taxa_letalidade_percentual
FROM vw_acidentes_enriquecida
GROUP BY fim_de_semana
ORDER BY fim_de_semana DESC;


-- Questão 5 - Lift por tipo de acidente:
-- calcula a taxa global e o Lift de cada tipo, considerando
-- somente tipos com pelo menos 100 registros.
WITH taxa_global AS (
    SELECT
        1.0 * SUM(acidente_fatal) / NULLIF(COUNT(*), 0) AS taxa_global
    FROM vw_acidentes_enriquecida
),
taxa_tipo AS (
    SELECT
        tipo_acidente,
        COUNT(*) AS total_acidentes,
        SUM(acidente_fatal) AS acidentes_fatais,
        1.0 * SUM(acidente_fatal) / NULLIF(COUNT(*), 0) AS taxa_tipo
    FROM vw_acidentes_enriquecida
    GROUP BY tipo_acidente
    HAVING COUNT(*) >= 100
)
SELECT
    t.tipo_acidente,
    t.total_acidentes,
    t.acidentes_fatais,
    ROUND(100.0 * t.taxa_tipo, 2) AS taxa_letalidade_percentual,
    ROUND(t.taxa_tipo / NULLIF(g.taxa_global, 0), 2) AS lift
FROM taxa_tipo t
CROSS JOIN taxa_global g
ORDER BY lift DESC, t.total_acidentes DESC;


-- Questão 6 - Ranking das causas associadas à letalidade:
-- retorna as cinco causas com maior Lift em relação à taxa global.
WITH taxa_global AS (
    SELECT
        1.0 * SUM(acidente_fatal) / NULLIF(COUNT(*), 0) AS taxa_global
    FROM vw_acidentes_enriquecida
),
taxa_causa AS (
    SELECT
        causa_acidente,
        COUNT(*) AS total_acidentes,
        SUM(acidente_fatal) AS acidentes_fatais,
        1.0 * SUM(acidente_fatal) / NULLIF(COUNT(*), 0) AS taxa_causa
    FROM vw_acidentes_enriquecida
    GROUP BY causa_acidente
)
SELECT
    c.causa_acidente,
    c.total_acidentes,
    c.acidentes_fatais,
    ROUND(100.0 * c.taxa_causa, 2) AS taxa_letalidade_percentual,
    ROUND(c.taxa_causa / NULLIF(g.taxa_global, 0), 2) AS lift
FROM taxa_causa c
CROSS JOIN taxa_global g
ORDER BY lift DESC, c.total_acidentes DESC
LIMIT 5;


-- Questão 7 - Infraestrutura / traçado da via:
-- compara a taxa de letalidade dos traçados com mais de 500 acidentes.
SELECT
    tracado_via,
    COUNT(*) AS total_acidentes,
    SUM(mortos) AS total_vitimas_fatais,
    SUM(acidente_fatal) AS total_acidentes_fatais,
    ROUND(100.0 * SUM(acidente_fatal) / NULLIF(COUNT(*), 0), 2)
        AS taxa_letalidade_percentual
FROM vw_acidentes_enriquecida
GROUP BY tracado_via
HAVING COUNT(*) > 500
ORDER BY taxa_letalidade_percentual DESC;


-- Questão 8 - Condições agravantes (pista x clima):
-- identifica as combinações com maior taxa de letalidade,
-- considerando somente grupos com pelo menos 50 acidentes.
SELECT
    tipo_pista,
    condicao_metereologica,
    COUNT(*) AS total_acidentes,
    SUM(mortos) AS total_vitimas_fatais,
    SUM(acidente_fatal) AS total_acidentes_fatais,
    ROUND(100.0 * SUM(acidente_fatal) / NULLIF(COUNT(*), 0), 2)
        AS taxa_letalidade_percentual
FROM vw_acidentes_enriquecida
GROUP BY tipo_pista, condicao_metereologica
HAVING COUNT(*) >= 50
ORDER BY taxa_letalidade_percentual DESC, total_acidentes DESC;


-- Questão 9 - Pontos críticos noturnos:
-- ranking das dez BRs com maior número absoluto de mortos
-- em acidentes ocorridos durante a fase Plena Noite.
SELECT
    br,
    COUNT(*) AS total_acidentes_noturnos,
    SUM(mortos) AS total_vitimas_fatais
FROM vw_acidentes_enriquecida
WHERE LOWER(TRIM(fase_dia)) = 'plena noite'
GROUP BY br
ORDER BY total_vitimas_fatais DESC, total_acidentes_noturnos DESC
LIMIT 10;


-- Questão 10 - Efeito de períodos festivos:
-- compara acidentes, mortos e taxa de letalidade entre Fim de Ano,
-- Carnaval e dias Normais.
SELECT
    data_comemorativa,
    COUNT(*) AS total_acidentes,
    SUM(mortos) AS total_vitimas_fatais,
    SUM(acidente_fatal) AS total_acidentes_fatais,
    ROUND(100.0 * SUM(acidente_fatal) / NULLIF(COUNT(*), 0), 2)
        AS taxa_letalidade_percentual
FROM vw_acidentes_enriquecida
GROUP BY data_comemorativa
ORDER BY taxa_letalidade_percentual DESC;


-- Questão 11 - Acidentes de altíssima gravidade:
-- primeiro identifica o ranking dos estados para acidentes com
-- pelo menos três mortos.
SELECT
    uf,
    COUNT(*) AS total_acidentes_com_3_ou_mais_mortos,
    SUM(mortos) AS total_vitimas_fatais
FROM vw_acidentes_enriquecida
WHERE mortos >= 3
GROUP BY uf
ORDER BY total_acidentes_com_3_ou_mais_mortos DESC,
         total_vitimas_fatais DESC;


-- Questão 11 - Principal causa no grupo de extrema gravidade:
-- identifica a causa mais frequente entre acidentes com >= 3 mortos.
SELECT
    causa_acidente,
    COUNT(*) AS total_ocorrencias,
    SUM(mortos) AS total_vitimas_fatais
FROM vw_acidentes_enriquecida
WHERE mortos >= 3
GROUP BY causa_acidente
ORDER BY total_ocorrencias DESC, total_vitimas_fatais DESC
LIMIT 1;


-- Questão 12 - Direcionamento regional em Pernambuco:
-- ranking dos cinco municípios com mais acidentes fatais em PE
-- considerando somente os anos de 2024 e 2025.
SELECT
    municipio,
    COUNT(*) AS total_acidentes_fatais,
    SUM(mortos) AS total_vitimas_fatais
FROM vw_acidentes_enriquecida
WHERE uf = 'PE'
  AND ano_acidente IN (2024, 2025)
  AND acidente_fatal = 1
GROUP BY municipio
ORDER BY total_acidentes_fatais DESC,
         total_vitimas_fatais DESC
LIMIT 5;
