-- Demand Optimization: Cortex Agent
USE SCHEMA MANUFACTURING_DEMAND.AI;

CREATE OR REPLACE AGENT DEMAND_PLANNING_AGENT
    COMMENT = 'Demand planning and optimization agent for manufacturing operations'
    PROFILE = '{"display_name": "Demand Planning Agent", "color": "purple"}'
    FROM SPECIFICATION
    $$
    models:
      orchestration: auto

    orchestration:
      budget:
        seconds: 30
        tokens: 16000

    instructions:
      response: "Provide concise, data-driven answers about demand planning, forecast accuracy, inventory health, and supply chain optimization. Use tables and numbers to support your answers."
      orchestration: "For questions about metrics, KPIs, forecast accuracy, inventory levels, or demand trends, use the DemandAnalyst tool. For questions about planning strategies, vendor guides, promotion calendars, or category plans, use the PlanningSearch tool."
      system: "You are a demand planning expert helping manufacturing teams optimize their forecasting, inventory management, and supply chain operations. Key context: Electronics category has 58% forecast accuracy (target 85%), 45 days of supply (target 21), and generates most rush purchase orders due to a seasonal demand shift not captured by the static forecasting model."
      sample_questions:
        - question: "Which category has the lowest forecast accuracy?"
          answer: "I'll query the forecast accuracy data to find the worst performing category."
        - question: "How many SKUs are at stockout risk?"
          answer: "I'll check the inventory health data for stockout risk levels."
        - question: "What is the total value at risk?"
          answer: "I'll calculate the total value at risk across all inventory positions."

    tools:
      - tool_spec:
          type: "cortex_analyst_text_to_sql"
          name: "DemandAnalyst"
          description: "Analyzes structured demand planning data including forecast accuracy by category, inventory days of supply, demand growth trends, and value at risk. Use for questions about metrics, KPIs, comparisons between categories, and quantitative analysis."
      - tool_spec:
          type: "cortex_search"
          name: "PlanningSearch"
          description: "Searches planning documents including demand strategies, category plans, promotion calendars, and vendor guides. Use for questions about policies, strategies, root causes, recommendations, and qualitative planning information."
      - tool_spec:
          type: "data_to_chart"
          name: "data_to_chart"
          description: "Generates visualizations from data returned by other tools."

    tool_resources:
      DemandAnalyst:
        semantic_view: "MANUFACTURING_DEMAND.AI.DEMAND_PLANNING_SEMANTIC_VIEW"
      PlanningSearch:
        name: "MANUFACTURING_DEMAND.SEARCH.PLANNING_DOCS_SEARCH"
        max_results: "5"
        title_column: "TITLE"
        id_column: "DOC_ID"
    $$;
