package com.example;

import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;

public class DummyApp {
    public static void main(String[] args) throws Exception {
        StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();
        env.execute("Dummy Flink SQL Application – does nothing");
    }
}