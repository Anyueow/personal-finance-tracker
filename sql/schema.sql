USE finance_tracker;

-- Savings recommendations
CREATE TABLE IF NOT EXISTS savings_recommendations (
    id INT AUTO_INCREMENT PRIMARY KEY,
    current_savings_rate DECIMAL(5,2) NOT NULL,
    benchmark_savings_rate DECIMAL(5,2) NOT NULL,
    suggested_areas JSON NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);