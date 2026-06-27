{% macro generate_database_name(custom_database_name, node) -%}

    {%- set default_database = target.database -%}

    {%- if target.name in ['dev', 'prod'] -%}
        {# In CI/CD targets, use the custom database if set #}
        {%- if custom_database_name is none -%}
            {{ default_database }}
        {%- else -%}
            {{ custom_database_name | trim }}
        {%- endif -%}
    {%- else -%}
        {# In developer targets, everything goes to the default database #}
        {{ default_database }}
    {%- endif -%}

{%- endmacro %}
