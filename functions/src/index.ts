import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import express from "express";
import cors from "cors";
import { ai } from "./auth0.js";
import { listEmails, readEmail } from "./tools/gmail.js";
import { listUpcomingEvents, createEvent } from "./tools/calendar.js";
import { listDriveFiles, readDriveFile } from "./tools/drive.js";
import type { MessageData } from "genkit/beta";

admin.initializeApp();
const db = admin.firestore();

const app = express();
app.use(cors({ origin: true }));
app.use(express.json());

const tools = [
  listEmails,
  readEmail,
  listUpcomingEvents,
  createEvent,
  listDriveFiles,
  readDriveFile,
];

const systemPrompt = `You are Beriwo, a personal assistant that helps users manage their Gmail, Google Calendar, and Google Drive.

Be direct and concise. When listing items, use a clean format. When errors occur related to authorization, tell the user they need to connect their Google account.

Do not make up data. Only use the tools provided.`;

app.post("/chat", async (req, res) => {
  const { message, conversationId } = req.body;

  if (!message) {
    res.status(400).json({ error: "message is required" });
    return;
  }

  const convoId = conversationId || admin.firestore().collection("tmp").doc().id;

  // Load conversation history
  const historySnap = await db
    .collection("conversations")
    .doc(convoId)
    .collection("messages")
    .orderBy("timestamp", "asc")
    .limit(50)
    .get();

  const messages: MessageData[] = historySnap.docs.map((doc) => {
    const d = doc.data();
    return { role: d.role as "user" | "model", content: [{ text: d.text }] };
  });

  // Store user message
  await db
    .collection("conversations")
    .doc(convoId)
    .collection("messages")
    .add({
      role: "user",
      text: message,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });

  try {
    const session = ai.createSession();
    const chat = session.chat({
      system: systemPrompt,
      tools,
    });

    const response = await chat.send(message);

    // Check for interrupts (Token Vault auth needed)
    if (response.interrupts && response.interrupts.length > 0) {
      const interrupt = response.interrupts[0];
      res.json({
        conversationId: convoId,
        reply: null,
        interrupt: {
          type: "authorization_required",
          data: interrupt.metadata,
        },
      });
      return;
    }

    const reply = response.text;

    // Store assistant response
    await db
      .collection("conversations")
      .doc(convoId)
      .collection("messages")
      .add({
        role: "model",
        text: reply,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });

    res.json({ conversationId: convoId, reply });
  } catch (err: unknown) {
    const error = err as Error;
    console.error("Chat error:", error.message);
    res.status(500).json({ error: "Failed to process message" });
  }
});

// Resume after user completes Token Vault authorization.
// Re-sends the last user message; the token is now stored in the vault
// so the tools will proceed without interrupting.
app.post("/conversations/:id/resume", async (req, res) => {
  const { id } = req.params;

  try {
    // Get the last user message
    const lastMsgSnap = await db
      .collection("conversations")
      .doc(id)
      .collection("messages")
      .where("role", "==", "user")
      .orderBy("timestamp", "desc")
      .limit(1)
      .get();

    if (lastMsgSnap.empty) {
      res.status(400).json({ error: "No user message found to resume" });
      return;
    }

    const lastMessage = lastMsgSnap.docs[0].data().text;

    // Load full history
    const historySnap = await db
      .collection("conversations")
      .doc(id)
      .collection("messages")
      .orderBy("timestamp", "asc")
      .limit(50)
      .get();

    const messages: MessageData[] = historySnap.docs.map((doc) => {
      const d = doc.data();
      return { role: d.role as "user" | "model", content: [{ text: d.text }] };
    });

    // Re-run with a fresh session. Token Vault now has the authorized token.
    const session = ai.createSession();
    const chat = session.chat({
      system: systemPrompt,
      tools,
    });

    const response = await chat.send(lastMessage);
    const reply = response.text;

    await db
      .collection("conversations")
      .doc(id)
      .collection("messages")
      .add({
        role: "model",
        text: reply,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });

    res.json({ conversationId: id, reply });
  } catch (err: unknown) {
    const error = err as Error;
    console.error("Resume error:", error.message);
    res.status(500).json({ error: "Failed to resume conversation" });
  }
});

export const api = functions.https.onRequest(app);
