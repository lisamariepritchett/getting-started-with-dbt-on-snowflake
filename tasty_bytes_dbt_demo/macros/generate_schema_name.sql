{% macro generate_schema_name(custom_schema_name, node) -%}

    {%- set default_schema = target.schema -%}

    {%- if target.name == 'prod' -%}
        {# In prod, use the custom schema (department folder) if set #}
        {%- if custom_schema_name is none -%}
            {{ default_schema }}
        {%- else -%}
            {{ custom_schema_name | trim }}
        {%- endif -%}
    {%- else -%}
        {# In all other targets (dev, dev_lisa, etc.), flatten into one schema #}
        {{ default_schema }}
    {%- endif -%}

{%- endmacro %}
