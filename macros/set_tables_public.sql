{% macro set_tables_public() %}

  {% set tables = [
    'daily_market_info',
    'daily_market_stats',
    'all_user_transactions',
    'daily_user_stats'
  ] %}

  {% for table in tables %}
    {% set sql %}
      ALTER TABLE dune.xvslove_team.{{ table }}
      SET PROPERTIES extra_properties = map_from_entries(ARRAY[ROW('dune.public', 'true')])
    {% endset %}
    {{ log("Setting " ~ table ~ " to public...", info=True) }}
    {% do run_query(sql) %}
    {{ log(table ~ " done.", info=True) }}
  {% endfor %}

{% endmacro %}
