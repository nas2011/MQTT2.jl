# MQTT2.jl Roadmap

This document outlines the planned improvements and features for the MQTT2.jl library. These enhancements aim to make the client more robust, secure, and fully compliant with advanced MQTT 5.0 features.

## 1. Auto-Reconnect and Session Resumption
*   **Feature:** Implement an automatic reconnection mechanism with exponential backoff (3^n seconds) and MQTT 5.0 session resumption support.
*   **Why it's useful:** Ensures high availability in unstable network environments. Session resumption (Clean Start = false) allows the client to retrieve missed messages and maintain subscriptions without re-subscribing.
*   **Implementation Requirements:**
    *   [x] Add a `reconnectLoop` in `client.jl`.
    * [x] Maintain a state of unacknowledged QoS 1/2 messages for session resumption.
    *   [x] Update `TopicSubscription` to store original `QoS` and `Properties` for faithful re-subscription.
    * [x] Store active subscriptions to replay them if the session cannot be resumed (`sessionPresent=false`).
    * [x] Expose `onConnect` and `onDisconnect` callbacks in `MqttClient`.

## 2. Last Will and Testament
*   **Feature:** Support specifying a "Last Will" message at connection, including QoS, Retain, and Properties. [x]
*   **Why it's useful:** Allows the broker to notify other clients if this client disconnects unexpectedly.
*   **Implementation Requirements:**
    *   [x] Update `ClientConfig` to include Will fields.
    *   [x] Integrate Will fields into `ConnectPacket` generation in `connect!` and `reconnect!`.
    *   [x] Verify Will encoding with automated tests.

## 3. TLS/SSL Security
*   **Feature:** Integration with `MbedTLS.jl` or `OpenSSL.jl` for encrypted communication (port 8883).
*   **Why it's useful:** Essential for production security, preventing eavesdropping and enabling client certificate-based authentication.
*   **Implementation Requirements:**
    *   Update `ClientConfig` to include SSL options (CA certs, client certs, private keys).
    *   Modify `connect!` to wrap the `TCPSocket` in an SSL stream when configured.

## 4. Topic Alias Management (MQTT 5.0)
*   **Feature:** Automatic mapping of long topic strings to short integer aliases.
*   **Why it's useful:** Significantly reduces bandwidth usage for frequent messages on the same topic, which is critical for constrained IoT networks.
*   **Implementation Requirements:**
    *   Maintain a bi-directional mapping of `Topic <-> Alias` in `MqttClient`.
    *   Automatically assign and use aliases based on the `topicAliasMaximum` property received from the broker in `CONNACK`.

## 5. Flow Control & Quota Management (MQTT 5.0)
*   **Feature:** Respect `Receive Maximum` and other flow control properties.
*   **Why it's useful:** Prevents the client and broker from overwhelming each other with too many in-flight QoS 1/2 messages.
*   **Implementation Requirements:**
    *   Track the number of in-flight outgoing packets and pause `publish!` if the broker's `receiveMaximum` limit is reached.
    *   Enforce a local limit on incoming packets to protect client resources.

## 6. Request-Response Pattern (MQTT 5.0)
*   **Feature:** High-level `request!` API that utilizes `Response Topic` and `Correlation Data`.
*   **Why it's useful:** Simplifies RPC-style interactions over MQTT, making it easier to build command-and-control systems.
*   **Implementation Requirements:**
    *   Add a `request!(client, topic, payload; responseTopic)` function.
    *   Manage temporary subscriptions or internal routing to return the response as a future or via a callback.

## 7. Shared Subscriptions Helper
*   **Feature:** Ergonomic support for Shared Subscriptions (`$share/GROUP/TOPIC`).
*   **Why it's useful:** Facilitates load balancing of message processing across multiple Julia workers or client instances.
*   **Implementation Requirements:**
    *   Validate and correctly parse shared subscription filters.
    *   Ensure `TopicSubscription` logic correctly handles the special prefix for matching if broker-side identifiers aren't used.

## 8. WebSockets Support
*   **Feature:** Enable MQTT communication over WebSockets.
*   **Why it's useful:** Allows the client to work in restricted network environments (e.g., only ports 80/443 open) or interact with WebSocket-only brokers.
*   **Implementation Requirements:**
    *   Integrate `HTTP.jl` or `WebSockets.jl`.
    *   Provide a WebSocket stream that satisfies the `IO` interface used by the existing packet encoder/decoder.

## 9. Enhanced Logging and Observability
*   **Feature:** Structured logging and metric hooks.
*   **Why it's useful:** Improves debuggability and allows integration with monitoring tools (e.g., Prometheus via `MicroMetrics.jl`).
*   **Implementation Requirements:**
    *   Standardize log levels (Info for connects, Debug for packets).
    *   Add hooks for tracking packet counts, latency, and error rates.
