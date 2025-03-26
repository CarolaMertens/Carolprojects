/*Combining tables with relevant columns using the last 12-month data
The last 12-month data will be used for KPIs and forecasts */
SELECT DISTINCT productName, productLine,
       quantityInStock, quantityOrdered,
       buyPrice, priceEach,
       orderDate, requiredDate,                
       shippedDate, status,
       warehouseName, warehousePctCap
FROM mintclassics.products AS products
JOIN mintclassics.warehouses As warehouses                  
ON products.warehouseCode=warehouses.warehouseCode
JOIN mintclassics.orderdetails As orderdetails
ON products.productCode=orderdetails.productCode
JOIN mintclassics.orders As orders
ON orderdetails.orderNumber=orders.orderNumber
WHERE orderDate>="2004-06-01" ;


/*Checking reasons for unshipped orders. 
Unshipped orders were either cancelled by the customers due to some disputes, 
on hold because of exceeding credit limit or in shipping process*/
SELECT orderDate, shippedDate, status, comments
FROM mintclassics.orders 
WHERE orderDate>="2004-06-01" AND status <> "Shipped";


/*Calculating correlation coefficient between price and sales using the last 12-month data.
('Shipped' orders show perfection of the sale process.)
The value is near 0, indicating that variables are independent of each other.*/
SELECT (COUNT(*) * SUM(quantityOrdered*priceEach)-SUM(quantityOrdered)*SUM(priceEach))/
(SQRT(COUNT(*)*SUM(quantityOrdered*quantityOrdered)-SUM(quantityOrdered)*SUM(quantityOrdered))*
SQRT(COUNT(*)*SUM(priceEach*priceEach)-SUM(priceEach)*SUM(priceEach))) AS corr_coefficient
FROM mintclassics.orderdetails AS orderdetails
JOIN mintclassics.orders AS orders
ON orders.orderNumber=orderdetails.orderNumber 
WHERE orderDate>="2004-06-01" AND status="Shipped";


/*Calculating revenue, profit, daily average sale and profit ratio, and comparing them to 
start_inventory$ and end_inventory$ using the last 12-month data.*/
SELECT DISTINCT revenue.productName, CONCAT('$',FORMAT(SUM(revenue),2)) AS total_revenue, 
	   CONCAT('$',FORMAT(SUM(profit),2)) AS total_profit, 
	   CONCAT('$',FORMAT(daily_avg_sales* AVG(priceEach),2)) AS daily_avg_sales$,
	   CONCAT(FORMAT(SUM(profit)/SUM(quantityOrdered),0),'%') AS profit_ratio,
       start_inventory$, end_inventory$
       #((forecast_start_inv$+forecast_end_inv$)/2) 
FROM (SELECT productName, quantityOrdered, priceEach,
	         (priceEach-buyPrice)*quantityOrdered AS profit,
			 quantityOrdered*priceEach AS revenue
			 FROM mintclassics.products AS products
			 JOIN mintclassics.orderdetails AS mintorderdetails
			 ON products.productCode=mintorderdetails.productCode
			 JOIN mintclassics.orders AS mintorders
			 ON mintorderdetails.orderNumber=mintorders.orderNumber
			 WHERE status = "Shipped" AND orderDate>="2004-06-01" 
			 GROUP BY productName, quantityOrdered, priceEach, buyPrice
	  ) AS revenue
JOIN (SELECT productName, 
			 CONCAT('$',FORMAT(quantityInStock*AVG(buyPrice),2)) AS start_inventory$,
			 CONCAT('$',FORMAT((quantityInStock-SUM(quantityOrdered))*AVG(buyPrice),2)) AS end_inventory$,
			 SUM(quantityOrdered)/12/30 AS daily_avg_sales
	  FROM mintclassics.products AS products
	  JOIN mintclassics.orderdetails AS mintorderdetails
	  ON products.productCode=mintorderdetails.productCode
	  JOIN mintclassics.orders AS mintorders
	  ON mintorderdetails.orderNumber=mintorders.orderNumber
      WHERE status="Shipped" AND orderDate>="2004-06-01" 
      GROUP BY productName,quantityInStock 
	  ) AS inv 
ON revenue.productName=inv.productName
GROUP BY productName, start_inventory$, end_inventory$, daily_avg_sales
ORDER BY profit_ratio DESC; 


/*Calculating revenue_share and cumulative_turnover using sales and price for ABC_analysis 
based on the last 12-month data.*/
SELECT ROW_NUMBER() OVER (ORDER BY revenue_share DESC) AS ranking, productName, revenue_share,  
	   @running_total := FORMAT(@running_total + revenue_share,2) AS cumulative_turnover
FROM (SELECT DISTINCT pvalue.productName,
			CONCAT(FORMAT((product_revenue/total_revenue)*100,2),"%") AS revenue_share
	  FROM (SELECT DISTINCT productName, 
						SUM(revenue) AS product_revenue
			FROM (SELECT productName, quantityOrdered, priceEach, 
							quantityOrdered*priceEach AS revenue
				  FROM mintclassics.products AS products
				  JOIN mintclassics.orderdetails As orderdetails
				  ON products.productCode=orderdetails.productCode
				  JOIN mintclassics.orders As orders
				  ON orderdetails.orderNumber=orders.orderNumber
				  WHERE status= "Shipped" AND orderDate>="2004-06-01"
				  GROUP BY productName, quantityOrdered, priceEach) AS svalue
			GROUP BY productName) AS pvalue
		CROSS JOIN (SELECT SUM(product_revenue) AS total_revenue
					FROM (SELECT DISTINCT productName, 
								SUM(revenue) AS product_revenue
						  FROM (SELECT productName, quantityOrdered, priceEach, 
										quantityOrdered*priceEach AS revenue
								FROM mintclassics.products AS products
								JOIN mintclassics.orderdetails As orderdetails
								ON products.productCode=orderdetails.productCode
								JOIN mintclassics.orders As orders
								ON orderdetails.orderNumber=orders.orderNumber
								WHERE status= "Shipped" AND orderDate>="2004-06-01"
								GROUP BY productName, quantityOrdered, priceEach) AS svalue
						   GROUP BY productName) AS pvalue) AS tvalue
		 GROUP BY productName, product_revenue, total_revenue
		 ORDER BY revenue_share DESC ) AS rshare
JOIN (SELECT @running_total :=0) r
ORDER BY revenue_share DESC;	  
 

#Calculating coefficient_variable for XYZ_analysis based on sales for the last 12-month data.
SELECT DISTINCT productName, sales.productCode, 
		CONCAT(FORMAT((stdev_daily_demand/avg_sales)*100,2),"%") AS coefficient_variation
FROM (SELECT DISTINCT qty.productCode, 
	         stddev_samp(sum_sales) AS stdev_daily_demand  
	  FROM (SELECT productCode,  
				   MONTH(orderDate) AS mo_ordered, 
				   SUM(quantityOrdered) AS sum_sales
			FROM mintclassics.orderdetails 
			JOIN mintclassics.orders AS orders
			ON orderdetails.orderNumber=orders.orderNumber
			WHERE status= "Shipped" AND orderDate>="2004-06-01" 
			GROUP BY  MONTH(orderDate), productCode
			ORDER BY mo_ordered
			) AS qty
		GROUP BY productCode
        ) AS sales
JOIN (SELECT DISTINCT products.productCode, AVG(quantityOrdered) AS avg_sales
	  FROM mintclassics.products AS products
      JOIN mintclassics.orderdetails AS mintorderdetails
	  ON products.productCode=mintorderdetails.productCode
      JOIN mintclassics.orders AS mintorders
      ON mintorderdetails.orderNumber=mintorders.orderNumber
      WHERE status= "Shipped" AND orderDate>="2004-06-01" 
	  GROUP BY productCode
      ) AS average
ON sales.productCode=average.productCode
JOIN mintclassics.products AS products
ON products.productCode=sales.productCode
GROUP BY productName, productCode, coefficient_variation;


#Combining ABC_analysis and XYZ_analysis
WITH abcxyz_analysis AS
(SELECT DISTINCT ranking, cumulative.productName, total_sales, 
		CONCAT(FORMAT(ranking/number_items*100,2),"%") AS item_share, 
		revenue_share, cumulative_turnover, coefficient_variation
FROM (SELECT ROW_NUMBER() OVER (ORDER BY revenue_share DESC) AS ranking, 
			productName, total_sales, revenue_share,  
			@running_total := FORMAT(@running_total + revenue_share,2) AS cumulative_turnover
	  FROM (SELECT DISTINCT pvalue.productName, total_sales,
				CONCAT(FORMAT((product_revenue/total_revenue)*100,2),"%") AS revenue_share
			FROM (SELECT DISTINCT productName, SUM(quantityOrdered) AS total_sales, 
							SUM(revenue) AS product_revenue
			      FROM (SELECT productName, quantityOrdered,  
								quantityOrdered*priceEach AS revenue
						FROM mintclassics.products AS products
						JOIN mintclassics.orderdetails As orderdetails
						ON products.productCode=orderdetails.productCode
						JOIN mintclassics.orders As orders
						ON orderdetails.orderNumber=orders.orderNumber
						WHERE status= "Shipped" AND orderDate>="2004-06-01"
						GROUP BY productName, quantityOrdered, priceEach
                        ) AS svalue
					GROUP BY productName
                    ) AS pvalue
			  CROSS JOIN (SELECT SUM(product_revenue) AS total_revenue
						  FROM (SELECT DISTINCT productName, 
									SUM(revenue) AS product_revenue
								FROM (SELECT productName, quantityOrdered, priceEach, 
											quantityOrdered*priceEach AS revenue
									  FROM mintclassics.products AS products
									  JOIN mintclassics.orderdetails As orderdetails
									  ON products.productCode=orderdetails.productCode
									  JOIN mintclassics.orders As orders
									  ON orderdetails.orderNumber=orders.orderNumber
									  WHERE status= "Shipped" AND orderDate>="2004-06-01"
									  GROUP BY productName, quantityOrdered, priceEach) AS svalue
							GROUP BY productName) AS pvalue) AS tvalue
				GROUP BY productName, product_revenue, total_revenue
				ORDER BY revenue_share DESC 
                ) AS vshare
		JOIN (SELECT @running_total :=0) r
		ORDER BY revenue_share DESC 
        ) AS cumulative
CROSS JOIN (SELECT COUNT(productName) AS number_items
			FROM mintclassics.products AS products ) AS items 
JOIN (SELECT DISTINCT productName, sales.productCode, 
		     CONCAT(FORMAT((stdev_daily_demand/avg_sales)*100,2),"%") AS coefficient_variation
	  FROM (SELECT DISTINCT qty.productCode, 
				   stddev_samp(sum_sales) AS stdev_daily_demand  
			FROM (SELECT productCode,  
						 MONTH(orderDate) AS mo_ordered, 
						 SUM(quantityOrdered) AS sum_sales
				  FROM mintclassics.orderdetails 
				  JOIN mintclassics.orders AS orders
				  ON orderdetails.orderNumber=orders.orderNumber
				  WHERE status= "Shipped" AND orderDate>="2004-06-01" 
				  GROUP BY  MONTH(orderDate), productCode
				  ORDER BY mo_ordered
				  ) AS qty
			GROUP BY productCode
			) AS sales
	  JOIN (SELECT DISTINCT products.productCode, AVG(quantityOrdered) AS avg_sales
			FROM mintclassics.products AS products
			JOIN mintclassics.orderdetails AS mintorderdetails
			ON products.productCode=mintorderdetails.productCode
			JOIN mintclassics.orders AS mintorders
			ON mintorderdetails.orderNumber=mintorders.orderNumber
			WHERE status= "Shipped" AND orderDate>="2004-06-01" 
			GROUP BY productCode
			) AS average
	  ON sales.productCode=average.productCode
	  JOIN mintclassics.products AS products
	  ON products.productCode=sales.productCode
	  GROUP BY productName, productCode, coefficient_variation
	  ) AS coeff_var
ON cumulative.productName=coeff_var.productName
GROUP BY ranking, productName, number_items, revenue_share, cumulative_turnover, coefficient_variation
ORDER BY ranking ASC
)
SELECT DISTINCT abc.productName, total_sales, item_share, revenue_share, 
	   cumulative_turnover, coefficient_variation, ABC_analysis, XYZ_analysis
FROM (SELECT productName, 
      CASE 
	   WHEN cumulative_turnover <= 40
        THEN "A"
       WHEN cumulative_turnover >40 AND cumulative_turnover <= 80
		THEN "B"
       ELSE "C"
       END AS ABC_analysis
	  FROM abcxyz_analysis
      ) AS abc 
JOIN (SELECT productName,
	  CASE
        WHEN coefficient_variation <= 40
        THEN "X"
      WHEN coefficient_variation > 40 AND coefficient_variation <= 60
        THEN "Y"
	  ELSE "Z"
	  END AS XYZ_analysis
      FROM abcxyz_analysis
      ) AS xyz
ON xyz.productName= abc.productName
JOIN abcxyz_analysis AS analysis
ON abc.productName=analysis.productName;	  


/*Calculating company lead time, customer lead time, delays and service rate using the last 12-month data.
Negative value means no delay */
WITH lead_time AS
		(SELECT orderNumber, DATEDIFF(shippedDate, orderDate) AS company_leadTime, 
			DATEDIFF(requiredDate, orderDate) AS customer_leadTime
		FROM  mintclassics.orders AS orders
        WHERE status = "Shipped" AND orderDate>="2004-06-01" ),
	delay_delivery AS
		(SELECT orderNumber, (company_leadTime - customer_leadTime) AS delay
        FROM lead_time AS lt
        GROUP BY orderNumber, company_leadTime, customer_leadTime),
	service_rate AS
        (SELECT orderNumber, 
	       CASE 
           WHEN company_leadTime >=0
            THEN  100
		   ELSE 0
           END AS serviceRate
	     FROM lead_time)
SELECT p.productName, 
	   FORMAT(AVG(company_leadTime),2) AS avg_comp_leadTime, 
	   FORMAT(AVG(customer_leadTime),2) AS avg_cust_leadTime, 
       FORMAT(AVG(delay),2) AS avg_delay,
       serviceRate
FROM mintclassics.products AS p
JOIN mintclassics.orderdetails AS od
ON p.productCode=od.productCode
JOIN lead_time AS lt
ON od.orderNumber=lt.orderNumber
JOIN delay_delivery AS dd
ON lt.orderNumber=dd.orderNumber
JOIN service_rate AS sr
ON lt.orderNumber=sr.orderNumber
GROUP BY productName, serviceRate
ORDER BY avg_delay ASC;


#Calculating standard deviation for safety_stock and reorder_point using the last 12-month data.       
SELECT productName, 
       FORMAT(stddev_samp(sales),2) AS stdev_daily_demand
FROM (SELECT productCode,  
             MONTH(orderDate) AS mo_ordered, 
	         SUM(quantityOrdered) AS sales       
	  FROM mintclassics.orderdetails #AS orderdetails
	  JOIN mintclassics.orders AS orders
	  ON orderdetails.orderNumber=orders.orderNumber
      WHERE status= "Shipped" AND orderDate>="2004-06-01" 
      GROUP BY  MONTH(orderDate), productCode
      ORDER BY mo_ordered
      ) AS qty
JOIN mintclassics.products AS products
ON products.productCode=qty.productCode
GROUP BY productName;  


#calculating KPIs for the last 12-month data; combining standard deviation and lead time with other factors
SELECT DISTINCT kpi.productName, quantityInStock, sales,
		FORMAT(((stddev_daily_demand*SQRT(avg_leadTime)*1.65)+daily_ave_sales*avg_leadTime),0) AS reorder_pt,
        FORMAT((stddev_daily_demand)*(SQRT(avg_leadTime))*1.65,0) AS safety_stock,
        CONCAT(FORMAT(sales/((quantityInStock+end_inventory)/2)*100,0),'%') AS inventory_turnover
FROM (SELECT productName, quantityInStock,
			 SUM(quantityOrdered) AS sales,
			 SUM(quantityOrdered)/12/30 AS daily_ave_sales,
			 AVG(DATEDIFF(shippedDate, orderDate)) AS avg_leadTime,
             (quantityInStock-SUM(quantityOrdered)) AS end_inventory
	  FROM mintclassics.products AS products
	  JOIN mintclassics.orderdetails AS mintorderdetails
	  ON products.productCode=mintorderdetails.productCode
	  JOIN mintclassics.orders AS mintorders
	  ON mintorderdetails.orderNumber=mintorders.orderNumber
      WHERE status = "Shipped" AND orderDate>="2004-06-01" 
	  GROUP BY productName, quantityInStock
      ) AS kpi
JOIN (SELECT qty.productName, 
			 FORMAT(stddev_samp(sales),2) AS stddev_daily_demand
	  FROM (SELECT productName, 
            MONTH(orderDate) AS mo_ordered, 
			SUM(quantityOrdered) AS sales  
            FROM mintclassics.products AS products
	        JOIN mintclassics.orderdetails AS mintorderdetails
	        ON products.productCode=mintorderdetails.productCode
	        JOIN mintclassics.orders AS mintorders
	        ON mintorderdetails.orderNumber=mintorders.orderNumber
			WHERE status= "Shipped" AND orderDate>="2004-06-01" 
			GROUP BY MONTH(orderDate), productName
			ORDER BY mo_ordered
            ) AS qty
	  GROUP BY productName
      ) AS std
ON kpi.productName=std.productName;


#Checking contents of each warehouse by productLine
SELECT DISTINCT productline, warehouseName, SUM(quantityInStock) AS stock_qty,
       warehousePctCap AS percent_cap
FROM mintclassics.warehouses AS warehouse
JOIN mintclassics.products AS products
ON products.warehouseCode=warehouse.warehouseCode
GROUP BY warehouseName, warehousePctCap, productline
ORDER BY warehouseName;


#proposed warehouse per productline based on quantityInStock
SELECT DISTINCT proposed.productLine, sum(prod_qty) AS stock_qty, 
	   (SELECT warehouseName 
		FROM mintclassics.warehouses AS wh
        JOIN mintclassics.products AS pr
        ON wh.warehouseCode=pr.warehouseCode
		WHERE proposed.productLine=pr.productLine 
		GROUP BY productLine, warehouseName 
	   ) AS original_warehouse,
	   proposed.warehouseName AS proposed_warehouse
FROM (SELECT DISTINCT productName, productLine, 
     		quantityInStock AS prod_qty, 
	  CASE
		WHEN productLine ="Ships"
		THEN "West"
		WHEN productLine ="Trains"
		THEN "East"
		WHEN productLine ="Trucks and Buses"
		THEN "West"
	    ELSE warehouseName
	  END AS warehouseName
	  FROM mintclassics.products AS prod
      JOIN mintclassics.orderdetails AS details
      ON prod.productCode=details.productCode
      JOIN mintclassics.warehouses AS whouse
      ON prod.warehouseCode=whouse.warehouseCode
      JOIN mintclassics.orders AS ord
      ON details.orderNumber=ord.orderNumber
	  GROUP BY productName, productLine,  warehouseName, quantityInStock
	 ) AS proposed
GROUP BY productLine, proposed_warehouse
ORDER BY original_warehouse ASC;


#proposed warehouse with forecasted quantity and percent capacity based on quantityInStock
WITH new_warehouse AS
  (SELECT DISTINCT proposed.productLine, 
		(SELECT warehouseName 
		 FROM mintclassics.warehouses AS wh
         JOIN mintclassics.products AS pr
         ON wh.warehouseCode=pr.warehouseCode
		 WHERE proposed.productLine=pr.productLine 
		 GROUP BY productLine, warehouseName 
	     ) AS original_warehouse,
		proposed.warehouseName AS proposed_warehouse, 
        sum(new_qty) AS proposed_qty 
   FROM (SELECT DISTINCT productName, productLine, 
				quantityInStock AS new_qty,
		 CASE
		  WHEN productLine ="Ships"
		  THEN "West"
		  WHEN productLine ="Trains"
		  THEN "East"
		  WHEN productLine ="Trucks and Buses"
		  THEN "West"
		  ELSE warehouseName
	     END AS warehouseName
		 FROM mintclassics.products AS prod
		 JOIN mintclassics.orderdetails AS details
		 ON prod.productCode=details.productCode
		 JOIN mintclassics.warehouses AS whouse
		 ON prod.warehouseCode=whouse.warehouseCode
		 JOIN mintclassics.orders AS ord
		 ON details.orderNumber=ord.orderNumber
		 GROUP BY productName, productLine,  warehouseName, quantityInStock
		 ) As proposed
	GROUP BY productLine, proposed_warehouse
	ORDER BY proposed_warehouse DESC
   ) 
SELECT original_warehouse, orig_warehouse_qty, CONCAT(warehousePctCap,'%') AS pct_capacity, 
	   proposed_wareHouse, proposed_warehouse_qty,
	CONCAT(FORMAT((warehousePctCap*proposed_warehouse_qty)/orig_warehouse_qty,0),'%') AS proposed_pctCap
FROM (SELECT DISTINCT original_warehouse, 
			(SELECT SUM(quantityInStock) AS orig_WH_qty
			FROM mintclassics.products AS pr
			WHERE pr.warehouseCode=whs.warehouseCode
			) AS orig_warehouse_qty,
			(SELECT DISTINCT proposed_warehouse
			FROM new_warehouse AS newwh
			WHERE newwh.proposed_warehouse=whs.warehouseName
			GROUP BY proposed_warehouse, original_warehouse
			) AS proposed_wareHouse, 
			(SELECT SUM(proposed_qty) AS prop_WH_qty
			FROM new_warehouse AS nw
			WHERE nw.proposed_warehouse=neww.original_warehouse
			) AS proposed_warehouse_qty
	FROM new_warehouse AS neww
	JOIN mintclassics.warehouses AS whs
	ON neww.original_warehouse=whs.warehouseName
	JOIN mintclassics.products AS prod
	ON whs.warehouseCode=prod.warehouseCode
    ) AS nq
JOIN mintclassics.warehouses AS wr
ON wr.warehouseName=nq.original_warehouse
GROUP BY original_warehouse, proposed_wareHouse, proposed_pctCap, orig_warehouse_qty, 
proposed_warehouse_qty, warehousePctCap;


#forecasted inventory turnover if stock quantity is reduced at a certain percentage to prevent overstocks
WITH kpi AS
(SELECT DISTINCT kpi.productName, 
        FORMAT((stddev_daily_demand)*(SQRT(avg_leadTime))*1.65,0) AS safety_stock,
        FORMAT(((stddev_daily_demand*SQRT(avg_leadTime)*1.65)+daily_ave_sales*avg_leadTime),0) AS reorder_pt,
        CONCAT(FORMAT(sales/((quantityInStock+end_inventory)/2)*100,0),'%') AS inventory_turnover
FROM (SELECT productName, quantityInStock,
			 SUM(quantityOrdered) AS sales,
			 SUM(quantityOrdered)/12/30 AS daily_ave_sales,
			 AVG(DATEDIFF(shippedDate, orderDate)) AS avg_leadTime,
             (quantityInStock-SUM(quantityOrdered)) AS end_inventory
	  FROM mintclassics.products AS products
	  JOIN mintclassics.orderdetails AS mintorderdetails
	  ON products.productCode=mintorderdetails.productCode
	  JOIN mintclassics.orders AS mintorders
	  ON mintorderdetails.orderNumber=mintorders.orderNumber
      WHERE status = "Shipped" AND orderDate>="2004-06-01" 
	  GROUP BY productName, quantityInStock
      ) AS kpi
JOIN (SELECT qty.productName, 
			 FORMAT(stddev_samp(sales),2) AS stddev_daily_demand
	  FROM (SELECT productName, 
            MONTH(orderDate) AS mo_ordered, 
			SUM(quantityOrdered) AS sales  
            FROM mintclassics.products AS products
	        JOIN mintclassics.orderdetails AS mintorderdetails
	        ON products.productCode=mintorderdetails.productCode
	        JOIN mintclassics.orders AS mintorders
	        ON mintorderdetails.orderNumber=mintorders.orderNumber
			WHERE status= "Shipped" AND orderDate>="2004-06-01" 
			GROUP BY MONTH(orderDate), productName
			ORDER BY mo_ordered
            ) AS qty
	  GROUP BY productName
      ) AS std
ON kpi.productName=std.productName
)
SELECT DISTINCT kp.productName, sales, reorder_pt, safety_stock, quantityInStock, 
	    pct_reduction, forecast_qty, inventory_turnover, 
       CONCAT(FORMAT(sales/forecast_avg_stock*100,0),'%') AS forecast_inv_turnover,
       stock_to_purchase
FROM (SELECT fore_inv.productName, sales, pct_reduction, forecast_qty, 
			 (forecast_qty+(forecast_qty-sales))/2 AS forecast_avg_stock,
             CASE 
             WHEN sales > pro.quantityInStock 
             THEN sales - pro.quantityInStock
             ELSE 0
             END AS stock_to_purchase
	  FROM (SELECT products.productName, products.quantityInStock, sales, pct_reduction,
				   FORMAT(products.quantityInStock-(products.quantityInStock*(pct_reduction/100)),0) AS forecast_qty
			FROM (SELECT pr.productName, quantityInStock, sales, 
				  CASE 
				  WHEN quantityInStock > sales 
				  THEN CONCAT(FORMAT((((sales-quantityInStock)/-quantityInStock)*100),0),'%') 
                  #WHEN quantityInStock < sales
                  #THEN quantityInStock
                  ELSE '0%'
				  END pct_reduction
				  FROM (SELECT productName, SUM(quantityOrdered) AS sales
						FROM mintclassics.products AS products
						JOIN mintclassics.orderdetails AS mintorderdetails
						ON products.productCode=mintorderdetails.productCode
						JOIN mintclassics.orders AS mintorders
						ON mintorderdetails.orderNumber=mintorders.orderNumber
						WHERE status= "Shipped" AND orderDate>="2004-06-01" 
						GROUP BY productName
					   ) AS sa
	              JOIN mintclassics.products AS pr
                  ON pr.productName=sa.productName
				 ) AS foreqty
		     JOIN mintclassics.products AS products
             ON foreqty.productName=products.productName
			 GROUP BY productName, pct_reduction, quantityInStock
		    ) AS fore_inv 
	   JOIN mintclassics.products AS pro
       ON pro.productName=fore_inv.productName
       JOIN mintclassics.orderdetails AS ord
       ON ord.productCode=pro.productCode
       GROUP BY productName, sales, forecast_qty, pct_reduction, pro.quantityInStock
      ) AS forecast_stock
JOIN kpi AS kp
ON kp.productName=forecast_stock.productName
JOIN mintclassics.products AS prodn
ON forecast_stock.productName=prodn.productName;


#proposed warehouse with %reduced quantities based on sales
WITH new_warehouse AS
  (SELECT DISTINCT proposed.productLine, 
		(SELECT warehouseName 
		 FROM mintclassics.warehouses AS wh
         JOIN mintclassics.products AS pr
         ON wh.warehouseCode=pr.warehouseCode
		 WHERE proposed.productLine=pr.productLine 
		 GROUP BY productLine, warehouseName 
	     ) AS original_warehouse,
		proposed.warehouseName AS proposed_warehouse, 
        sum(reduced_qty) AS proposed_qty 
   FROM (SELECT DISTINCT productName, productLine, 
				SUM(quantityOrdered) AS reduced_qty,
		 CASE
		  WHEN productLine ="Vintage Cars"
		  THEN "South"
		  WHEN productLine ="Planes"
		  THEN "South"
		  WHEN productLine ="Motorcycles"
		  THEN "South"
          WHEN productLine ="Classic Cars"
		  THEN "South"
		  ELSE warehouseName
	     END AS warehouseName
		 FROM mintclassics.products AS prod
		 JOIN mintclassics.orderdetails AS details
		 ON prod.productCode=details.productCode
		 JOIN mintclassics.warehouses AS whouse
		 ON prod.warehouseCode=whouse.warehouseCode
		 JOIN mintclassics.orders AS ord
		 ON details.orderNumber=ord.orderNumber
         WHERE status= "Shipped" AND orderDate>="2004-06-01" 
		 GROUP BY productName, productLine,  warehouseName, quantityInStock
		 ) As proposed
	GROUP BY productLine, proposed_warehouse
	ORDER BY proposed_warehouse DESC
   ) 
SELECT original_warehouse, orig_warehouse_qty, CONCAT(warehousePctCap,'%') AS pct_capacity, 
	   proposed_wareHouse, proposed_warehouse_qty,
	CONCAT(FORMAT((warehousePctCap*proposed_warehouse_qty)/orig_warehouse_qty,0),'%') AS proposed_pctCap
FROM (SELECT DISTINCT original_warehouse, 
			(SELECT SUM(quantityInStock) AS orig_WH_qty
			FROM mintclassics.products AS pr
			WHERE pr.warehouseCode=whs.warehouseCode
			) AS orig_warehouse_qty,
			(SELECT DISTINCT proposed_warehouse
			FROM new_warehouse AS newwh
			WHERE newwh.proposed_warehouse=whs.warehouseName
			GROUP BY proposed_warehouse, original_warehouse
			) AS proposed_wareHouse, 
			(SELECT SUM(proposed_qty) AS prop_WH_qty
			FROM new_warehouse AS nw
			WHERE nw.proposed_warehouse=neww.original_warehouse
			) AS proposed_warehouse_qty
	FROM new_warehouse AS neww
	JOIN mintclassics.warehouses AS whs
	ON neww.original_warehouse=whs.warehouseName
	JOIN mintclassics.products AS prod
	ON whs.warehouseCode=prod.warehouseCode
    ) AS nq
JOIN mintclassics.warehouses AS wr
ON wr.warehouseName=nq.original_warehouse
GROUP BY original_warehouse, proposed_wareHouse, proposed_pctCap, orig_warehouse_qty, 
proposed_warehouse_qty, warehousePctCap;
