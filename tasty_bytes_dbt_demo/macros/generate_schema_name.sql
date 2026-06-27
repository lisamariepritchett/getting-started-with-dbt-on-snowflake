{% macro generate_schema_name(custom_schema_name, node) -%}

    {%- set default_schema = target.schema -%}

    {%- if target.name in ['dev', 'prod'] -%}
        {# In CI/CD targets, use the custom schema (department folder) if set #}
        {%- if custom_schema_name is none -%}
            {{ default_schema }}
        {%- else -%}
            {{ custom_schema_name | trim }}
        {%- endif -%}
    {%- else -%}
        {# In developer targets (dev_lisa, dev_bob), flatten everything into one schema #}
        {{ default_schema }}
    {%- endif -%}

{%- endmacro %}
