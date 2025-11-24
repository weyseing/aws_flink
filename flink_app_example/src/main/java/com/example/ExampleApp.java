package com.example;

import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.apache.flink.streaming.api.functions.source.SourceFunction;

public class ExampleApp {
    public static void main(String[] args) throws Exception {
        StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();

        env.addSource(new SourceFunction<Long>() {
                private volatile boolean isRunning = true;
                private long counter = 0;

                @Override
                public void run(SourceContext<Long> ctx) throws Exception {
                    while (isRunning) {
                        counter++;
                        System.out.println("Still alive - counter = " + counter + " (visible in CloudWatch)");
                        ctx.collect(counter);
                        Thread.sleep(1000);  
                    }
                }

                @Override
                public void cancel() {
                    isRunning = false;
                }
            })
            .print();  

        env.execute("Forever-Alive-Logger");
    }
}