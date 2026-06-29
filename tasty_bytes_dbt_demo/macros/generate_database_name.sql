-- Derives prod database from folder layer (staging/marts); uses default in dev
-- Co-authored with CoCo
{% macro generate_database_name(custom_database_name, node) -%}

    {%- set default_database = target.database -%}

    {%- if target.name == 'prod' -%}
        {# In prod, use custom database if explicitly set, otherwise derive from layer #}
        {%- if custom_database_name is not none -%}
            {{ custom_database_name | trim }}
        {%- elif node.fqn | length > 2 and node.fqn[1] == 'staging' -%}
            tasty_bytes_stage_db
        {%- elif node.fqn | length > 2 and node.fqn[1] == 'marts' -%}
            tasty_bytes_edw_db
        {%- else -%}
            {{ default_database }}
        {%- endif -%}
    {%- else -%}
        {# In all other targets, everything goes to the default database #}
        {{ default_database }}
    {%- endif -%}

{%- endmacro %}
