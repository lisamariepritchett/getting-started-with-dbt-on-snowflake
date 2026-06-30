-- Derives prod schema from folder structure; flattens to target schema in dev
-- Co-authored with CoCo
{% macro generate_schema_name(custom_schema_name, node) -%}

    {%- set default_schema = target.schema -%}

    {%- if target.name == 'prod' -%}
        {# In prod, use custom schema if explicitly set, otherwise derive from folder #}
        {%- if custom_schema_name is not none -%}
            {{ custom_schema_name | trim }}
        {%- elif node.fqn | length > 3 -%}
            {# fqn = [project, layer, folder, model] — use the folder as schema #}
            {{ node.fqn[-2] }}
        {%- else -%}
            {{ default_schema }}
        {%- endif -%}
    {%- else -%}
        {# In all other targets (dev, dev_lisa, etc.), flatten into one schema #}
        {{ default_schema }}
    {%- endif -%}

{%- endmacro %}
