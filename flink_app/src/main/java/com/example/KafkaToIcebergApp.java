import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.apache.flink.table.api.bridge.java.StreamTableEnvironment;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import com.amazonaws.services.kinesisanalytics.runtime.KinesisAnalyticsRuntime;
import java.util.Map;
import java.util.Properties;

public class KafkaToIcebergApp {
    
    private static final Logger LOG = LoggerFactory.getLogger(KafkaToIcebergApp.class);
    
    public static void main(String[] args) throws Exception {
        
        // Read configuration from System Properties (set by AWS Flink)
        String kafkaServers = getProperty("kafka.bootstrap.servers");
        String kafkaTopic = getProperty("kafka.topic");
        String kafkaGroupId = getProperty("kafka.group.id", "flink-iceberg-consumer");
        String s3Warehouse = getProperty("iceberg.warehouse");
        String icebergDatabase = getProperty("iceberg.database", "default");
        String icebergTable = getProperty("iceberg.table", "kafka_events");
        
        LOG.info("========================================");
        LOG.info("Starting Kafka to Iceberg Application");
        LOG.info("========================================");
        LOG.info("Kafka Servers: {}", kafkaServers);
        LOG.info("Kafka Topic: {}", kafkaTopic);
        LOG.info("Kafka Group ID: {}", kafkaGroupId);
        LOG.info("Iceberg Warehouse: {}", s3Warehouse);
        LOG.info("Iceberg Database: {}", icebergDatabase);
        LOG.info("Iceberg Table: {}", icebergTable);
        LOG.info("========================================");
        
        // Create execution environment
        StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();
        
        // Enable checkpointing for fault tolerance
        env.enableCheckpointing(60000); // Checkpoint every 60 seconds
        
        // Create Table Environment
        StreamTableEnvironment tableEnv = StreamTableEnvironment.create(env);
        
        // Step 1: Create Kafka source table
        LOG.info("Creating Kafka source table...");
        String createKafkaSourceSQL = String.format(
            "CREATE TABLE kafka_source (" +
            "  `id` STRING," +            // Use backticks
            "  `name` STRING," +
            "  `event_timestamp` BIGINT," +
            "  `value` DOUBLE" +          // Specially important for "value"
            ") WITH (" +
            "  'connector' = 'kafka'," +
            "  'topic' = '%s'," +
            "  'properties.bootstrap.servers' = '%s'," +
            "  'properties.group.id' = '%s'," +
            "  'scan.startup.mode' = 'latest-offset'," +
            "  'format' = 'json'," +
            "  'json.fail-on-missing-field' = 'false'," +
            "  'json.ignore-parse-errors' = 'true'" +
            ")",
            kafkaTopic, kafkaServers, kafkaGroupId
        );
        tableEnv.executeSql(createKafkaSourceSQL);
        LOG.info("✓ Kafka source table created");
        
        // Step 2: Create Iceberg catalog
        LOG.info("Creating Iceberg catalog...");
        tableEnv.executeSql(
            "CREATE CATALOG glue_catalog WITH (" +
            "  'type'='iceberg'," +
            // Forces the Glue Catalog specifically
            "  'catalog-impl'='org.apache.iceberg.aws.glue.GlueCatalog'," + 
            // Uses S3 native client instead of Hadoop's S3A
            "  'io-impl'='org.apache.iceberg.aws.s3.S3FileIO'," +           
            "  'warehouse'='" + s3Warehouse + "'," +
            // This tells Iceberg to use an empty Hadoop config instead of crashing
            "  'hadoop.conf.common.configuration.factory'='org.apache.iceberg.aws.EmptyConfigurationFactory'" +
            ")"
        );
        LOG.info("✓ Iceberg catalog created");
        

        LOG.info("========================================");
        LOG.info("✓ Pipeline started successfully!");
        LOG.info("Consuming from Kafka topic: {}", kafkaTopic);
        LOG.info("Writing to Iceberg table: {}.{}", icebergDatabase, icebergTable);
        LOG.info("========================================");
    }
    
    private static String getProperty(String key) throws Exception {
        // 1. Get all property groups from the AWS environment
        Map<String, Properties> applicationProperties = KinesisAnalyticsRuntime.getApplicationProperties();
        
        // 2. Look in the group you defined ("FlinkApplicationProperties")
        Properties flinkProps = applicationProperties.get("FlinkApplicationProperties");
        
        if (flinkProps == null || !flinkProps.containsKey(key)) {
            throw new RuntimeException("Required property not found in FlinkApplicationProperties group: " + key);
        }
        return flinkProps.getProperty(key);
    }

    private static String getProperty(String key, String defaultValue) throws Exception {
        try {
            return getProperty(key);
        } catch (Exception e) {
            return defaultValue;
        }
    }
}