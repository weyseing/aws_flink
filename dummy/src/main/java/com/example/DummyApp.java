package com.example;

import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;

public class DummyApp {
    public static void main(String[] args) throws Exception {
        StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();
        env.fromSequence(1, Long.MAX_VALUE)
           .map(value -> value)
           .print();                     // keeps job alive forever
        env.execute("Alive");
    }
}