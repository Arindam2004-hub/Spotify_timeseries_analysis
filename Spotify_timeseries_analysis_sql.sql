SELECT * FROM spotify.spotify_history;


-- Q1.What are the top 10 most-played album and artist  total listening time
SELECT  artist_name,album_name,ROUND((SUM(ms_played)/1000)/3600) AS total_listening_time_hour FROM spotify.spotify_history GROUP BY album_name,artist_name ORDER BY ROUND((SUM(ms_played)/1000)/3600) DESC LIMIT 10


-- Q2. What is the distribution of streams across platforms (web player, mobile, desktop, etc.)?

SELECT *,ROUND(total_listening_time_hour*100.0/SUM(total_listening_time_hour) OVER(),2) AS percent
FROM(SELECT platform,ROUND((SUM(ms_played)/1000)/3600) AS total_listening_time_hour   
FROM spotify.spotify_history 
GROUP BY platform 
ORDER BY ROUND((SUM(ms_played)/1000)/3600)DESC) t 

-- Q3.What percentage of tracks were skipped vs. fully played, and how does this vary by platform?
-- WHERE 0 = NOT SKIPPED SONG, 1= SKIPPED  SONG

SELECT platform,skipped,ROUND(total*100.0/SUM(total) OVER(PARTITION BY platform),2) AS percentage 
FROM(SELECT platform,skipped,
COUNT(*) AS total FROM spotify.spotify_history GROUP BY skipped,platform) t


-- Q4.How has monthly listening volume (total hours played) trended over the years?

SELECT CONCAT(year_ ,'--', month_name) AS year_month_,ROUND(((SUM(ms_played)/1000)/3600),2) AS total_played_hour
FROM(SELECT *,MONTHNAME(ts) AS month_name , YEAR(ts) AS year_
FROM   spotify.spotify_history) t GROUP BY month_name,year_ ORDER BY year_ DESC


-- Q5.What is the listening pattern by hour-of-day and day-of-week (a "listening heatmap")?

SELECT day_,time_of_the_day, ROUND(((SUM(ms_played)/1000)/3600),2) AS total_listen_hour
FROM (SELECT *,DAYNAME(ts) AS day_,HOUR(ts) AS time_of_the_day FROM spotify.spotify_history) t GROUP BY time_of_the_day,day_ ORDER BY day_ ,time_of_the_day


-- Q6.What is the most common "track start reason" and "track end reason" combination

SELECT reason_start,reason_end,COUNT(*) AS total_count FROM spotify.spotify_history GROUP BY reason_start,reason_end ORDER BY total_count DESC LIMIT 10

-- Q7.how does skip rate differ by reason_start (e.g., autoplay vs. clickrow vs. shuffle)?
SELECT 
    reason_start,
    COUNT(*) AS total_plays,
    SUM(CASE WHEN skipped = TRUE THEN 1 ELSE 0 END) AS skipped_count,
    ROUND(
        SUM(CASE WHEN skipped = TRUE THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 
        2
    ) AS skip_rate_pct
FROM spotify.spotify_history
GROUP BY reason_start
ORDER BY skip_rate_pct DESC;


-- Q8.What is the  completion rate  by artist

SELECT * 
FROM(SELECT artist_name,COUNT(*) AS total_song,
SUM(CASE WHEN skipped=0 THEN 1 ELSE 0 END) AS not_skipped,
SUM(CASE WHEN skipped=1 THEN 1 ELSE 0 END) AS skipped,
ROUND((SUM(CASE WHEN skipped=0 THEN 1 ELSE 0 END)*100.0/COUNT(*)),2) AS completion_rate 
FROM spotify.spotify_history GROUP BY artist_name HAVING COUNT(*)>20 ) t where completion_rate >=95 ORDER BY completion_rate DESC,total_song DESC



-- Q9.Which month-over-month artist is trending up the fastest in play count (breakout artists) in 2024?


SELECT * 
FROM(
    SELECT artist_name, month_name, last_month_name,
        ROUND((total_play_count - last_month_total_play) * 100.0 / last_month_total_play, 2) AS MONTH_OVER_MONTH_GROWTH_PERCENT
    FROM(
        SELECT *
        FROM(
            SELECT *,
                LAG(month_no) OVER (PARTITION BY artist_name ORDER BY month_no) AS last_month_no,
                LAG(month_name) OVER (PARTITION BY artist_name ORDER BY month_no) AS last_month_name,
                LAG(total_play_count) OVER (PARTITION BY artist_name ORDER BY month_no) AS last_month_total_play
            FROM(
                SELECT artist_name, month_name, month_no, COUNT(*) AS total_play_count
                FROM(
                    SELECT ts, artist_name, MONTH(ts) AS month_no, MONTHNAME(ts) AS month_name 
                    FROM spotify.spotify_history 
                    WHERE ts >= '2024-01-01' AND ts < '2025-01-01'
                ) t 
                GROUP BY artist_name, month_name, month_no
            ) p
        ) g 
        WHERE (month_no - last_month_no) = 1
    ) c
    WHERE last_month_total_play >= 5   -- minimum threshold to avoid noisy % growth
) k 
ORDER BY MONTH_OVER_MONTH_GROWTH_PERCENT DESC
LIMIT 10;


-- Q10.Calculate a rolling 7-day and 30-day moving average of daily listening time to smooth out trend noise and identify listening habit changes over time.

SELECT * 
FROM(SELECT *, 
CASE
	WHEN TREND_STATUS='ABOVE' AND PREVIOUS_DAY_TREND_STATUS='BELOW' THEN 'Picking up'
    WHEN TREND_STATUS='BELOW' AND PREVIOUS_DAY_TREND_STATUS='ABOVE' THEN 'Cooling_off'
    ELSE 'NO'
END AS CROSSOVER_EVENT
FROM(SELECT date_,MOVING_AVG_7_DAYS, MOVING_AVG_30_DAYS, TREND_STATUS,
LAG(TREND_STATUS) OVER(ORDER BY date_) AS PREVIOUS_DAY_TREND_STATUS
FROM(SELECT *,
CASE
	WHEN MOVING_AVG_7_DAYS> MOVING_AVG_30_DAYS THEN 'ABOVE' 
    ELSE 'BELOW'
END AS TREND_STATUS
FROM(SELECT *,AVG(total_listen_min) OVER(ORDER BY date_ ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS MOVING_AVG_7_DAYS,
AVG(total_listen_min) OVER(ORDER BY date_ ROWS BETWEEN 29 PRECEDING AND CURRENT ROW) AS MOVING_AVG_30_DAYS
FROM(SELECT date_ , ROUND((SUM(ms_played)/1000)/60,2) AS total_listen_min FROM(SELECT *,DATE(ts) AS date_ FROM spotify.spotify_history) t  GROUP BY date_ )p ) d) V) k)x WHERE CROSSOVER_EVENT IN('Cooling_off','Picking up')

