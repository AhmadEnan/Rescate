package com.rescate.tools;

import com.graphhopper.config.CHProfile;
import com.graphhopper.config.Profile;
import com.graphhopper.reader.osm.GraphHopperOSM;
import com.graphhopper.routing.util.EncodingManager;

public final class GenerateGraph {
    private GenerateGraph() {}

    public static void main(String[] args) {
        if (args.length != 2) {
            throw new IllegalArgumentException("Usage: GenerateGraph <input.osm> <output-graph-cache-dir>");
        }

        GraphHopperOSM hopper = new GraphHopperOSM();
        hopper.setOSMFile(args[0]);
        hopper.setGraphHopperLocation(args[1]);
        hopper.setEncodingManager(EncodingManager.create("car"));
        hopper.setProfiles(
            new Profile("car")
                .setVehicle("car")
                .setWeighting("fastest")
                .setTurnCosts(false)
        );
        hopper.getCHPreparationHandler().setCHProfiles(new CHProfile("car"));
        hopper.importOrLoad();
        hopper.close();
    }
}
