# Introducing Beriwo: A Network of AI Agents That Acts on Your Behalf

*Built for Auth0 Hackathon 2026*
*By Emmanuel Veranyuy Mfon*

---

We interact with chat assistants every single day, asking them to generate text, summarize documents, or write code. But what happens when you want an agent to actually *do* something for you? 

What if you could say: *"Check my email, find the itinerary for my trip tomorrow, put the flight details into my Google Calendar, and text my wife Tina to remind her to pick up my son Ethan"*?

General-purpose assistants fall short here. They lack the native authority to interact with personal data securely. They don't have a reliable memory of who your family members are, and handing over full read/write access to your digital life directly to a language model is a massive security risk.

Enter **Beriwo**.

## What is Beriwo?

Beriwo is a network of AI agents designed to act on your behalf. Unlike standard chatbots, Beriwo plans, executes secure tool calls, reflects on results, and synthesizes responses in a seamless, autonomous loop. 

With Beriwo, your AI takes action while keeping you entirely in control. 

## The Architecture of Trust

Building an autonomous agent requires a fundamentally different approach to security. Beriwo achieves this using a **Zero-Trust Architecture** powered by Auth0.

### 1. Auth0 Token Vault & Secure Proxies
To ensure absolute security, your Google API credentials never touch the underlying language model. Instead, Beriwo relies on the **Auth0 Token Vault**. When the agent identifies that it needs to perform an action (like reading an email or creating a calendar event), it routes the request through a secure proxy. The proxy attaches the necessary OAuth tokens on the fly, meaning the AI only ever sees the inputs and outputs, never the keys to your digital life. 

### 2. Fine-Grained Authorization (FGA)
We implemented **Auth0 FGA** to ensure that actions are tightly scoped. Reading a calendar event requires a different level of permission than booking a flight. FGA ensures that the agent's capabilities are strictly governed by explicit access policies that verify exactly what the agent is authorized to do at any given moment.

### 3. Consent-Gated Execution (Human-in-the-Loop)
Complete transparency is non-negotiable. Beriwo can read autonomously to gather context, but it hits a hard stop before altering anything. The system uses **Consent-Gated Execution**: whenever Beriwo generates a write-action (e.g., sending an email, purchasing a ticket, or modifying a document), it explicitly pauses and prompts you for approval. Nothing is written without your explicit, on-screen consent.

## How the Autonomous Pipeline Works

Beriwo isn't a simple request-response loop. It's a localized network utilizing a dynamic **3-Phase Pipeline**:

1. **Plan:** When you submit a request, Beriwo breaks the objective into actionable sub-tasks. 
2. **Execute:** It triggers secure tool calls through the Auth0-gated proxy, pinging external services (Gmail, Calendar, Drive) securely.
3. **Reflect:** It evaluates the payload returned by the APIs. If an API request fails, it adjusts the strategy and tries again before finally synthesizing the perfect response for you.

To make the experience seamless, Beriwo utilizes **Persistent Memory**. Cross-session memory builds a secure profile of your contexts, routines, and relationships, dynamically shaping how the agent supports you over time—without requiring you to re-explain who "Timeline" or "Ethan" is every session.

## Looking Forward

The era of AI as a conversational novelty is ending; the era of AI as an active, secure proxy is beginning. With Beriwo, we are proving that autonomous agents can be powerful, context-aware, and—most importantly—secure by design. 

By leveraging the Auth0 Token Vault and FGA, Beriwo provides the ultimate combination of autonomy and safety.

*Beriwo // Authorized to Act.*