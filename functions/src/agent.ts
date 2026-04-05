import { logger } from "firebase-functions/v2";
import { getAI, withTokens } from "./auth0.js";
import { getGmailTools } from "./tools/gmail.js";
import { getCalendarTools } from "./tools/calendar.js";

/**
 * Run autonomous background email checks.
 */
export async function runAutoPilot(userId: string, adminDb: any) {
  logger.info(`Running auto pilot for user: ${userId}`);

  // Fetch user memories to give the agent context
  const snap = await adminDb
    .collection("user_memory")
    .doc(userId)
    .collection("facts")
    .orderBy("timestamp", "desc")
    .limit(10)
    .get();

  const facts = snap.docs.map((d: any) => d.data().text).join("\n- ");
  
  const ai = getAI();
  const { listEmails, readEmail, sendEmail, replyToEmail } = getGmailTools();
  const { listUpcomingEvents, createEvent } = getCalendarTools();

  const tools = [
    listEmails,
    readEmail,
    sendEmail,
    replyToEmail,
    listUpcomingEvents,
    createEvent
  ];

  const sysPrompt = `
You are Beriwo, an autonomous AI operator for the user. 
Right now, you are running in a background cron job. 
Your goal is to autonomously manage the user's digital life while they are away.
Use the tools to check unread emails. If an email is important and needs a response right away, reply to it.
If an email requests a meeting, create the event on the calendar and reply confirming it.
If you find emails that are just newsletters or spam, you can ignore them.
Try to act as the user normally would. 

Important user context factors/memories:
${facts || "None"}

Please be conservative with sending emails, but do take action if it's clear what needs to happen.
Write down a brief summary of what you did when you finish.`;

  try {
    const result = await withTokens({ userId }, async () => {
      return ai.generate({
        prompt: sysPrompt,
        tools: tools,
      });
    });

    logger.info(`Auto Pilot summary for ${userId}: ${result.text}`);
    
    // Save activity
    await adminDb.collection("auto_pilot_logs").add({
      userId,
      log: result.text,
      timestamp: new Date(),
    });
    
  } catch (error) {
    logger.error(`Error in runAutoPilot for ${userId}:`, error);
  }
}
