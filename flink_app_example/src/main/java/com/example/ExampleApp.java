// flink_app_example/src/main/java/com/example/ExampleApp.java

package com.example;

import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;

public class ExampleApp {
    public static void main(String[] args) throws Exception {
        StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();
        env.fromSequence(1, Long.MAX_VALUE)
           .map(value -> value)
           .print();                     // keeps job alive forever
        env.execute("Alive");
    }
}