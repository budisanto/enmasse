/*
 * Copyright 2018, EnMasse authors.
 * License: Apache License 2.0 (see the file LICENSE or http://apache.org/licenses/LICENSE-2.0.html).
 */
package io.enmasse.systemtest.common;

import io.enmasse.systemtest.AddressSpace;
import io.enmasse.systemtest.AddressSpaceType;
import io.enmasse.systemtest.CustomLogger;
import io.enmasse.systemtest.bases.TestBase;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.slf4j.Logger;

import java.util.HashMap;

import static io.enmasse.systemtest.TestTag.isolated;

@Tag(isolated)
public class ServiceCatalog extends TestBase {
    private static Logger log = CustomLogger.getLogger();

    @Test
    void serviceCatalogApiTest() throws Exception {
        AddressSpace addressSpaceViaOSBAPIBrokered = new AddressSpace("myspace-via-osbapi-brokered", AddressSpaceType.BROKERED);
        createAddressSpaceViaServiceBroker(addressSpaceViaOSBAPIBrokered, "#");

        AddressSpace addressSpaceViaOSBAPIStandard = new AddressSpace("myspace-via-osbapi-standard", AddressSpaceType.STANDARD);
        createAddressSpaceViaServiceBroker(addressSpaceViaOSBAPIStandard, "*");
    }

    private void createAddressSpaceViaServiceBroker(AddressSpace addressSpace, String wildcardMark) throws Exception {
        String instanceId = createServiceInstance(addressSpace);

        HashMap<String, String> bindResources = new HashMap<>();
        bindResources.put("sendAddresses", String.format("queue.%s", wildcardMark));
        bindResources.put("receiveAddresses", String.format("queue.%s", wildcardMark));
        bindResources.put("consoleAccess", "true");
        bindResources.put("consoleAdmin", "false");
        bindResources.put("externalAccess", "false");
        String bindingId = generateBinding(addressSpace, instanceId, bindResources);

        //deleteBinding(bindingId);
        deleteServiceInstance(addressSpace, instanceId);
    }
}
