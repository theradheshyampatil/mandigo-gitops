// =============================================================================
// Wake Lambda — starts the MandiGo EC2 instance and stamps a WakeUntil tag.
//
// Invoked by the splash page's "Wake the project" button via a Lambda
// Function URL (public, no auth). The companion stop Lambda (cron) reads
// the WakeUntil tag to decide when to shut the instance back down.
//
// AWS SDK v3 is preinstalled in the nodejs20.x runtime — no bundling needed.
// =============================================================================

import {
  EC2Client,
  DescribeInstancesCommand,
  StartInstancesCommand,
  CreateTagsCommand,
} from "@aws-sdk/client-ec2";

const REGION = process.env.AWS_REGION || "ap-south-1";
const INSTANCE_ID = process.env.INSTANCE_ID;
const KEEP_ALIVE_MINUTES = parseInt(process.env.KEEP_ALIVE_MINUTES || "10", 10);

const ec2 = new EC2Client({ region: REGION });

// Permissive CORS so the static splash (on a different origin) can call us.
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "content-type",
  "content-type": "application/json",
};

const json = (statusCode, body) => ({
  statusCode,
  headers: CORS,
  body: JSON.stringify(body),
});

export const handler = async (event) => {
  // Function URL preflight
  const method = event?.requestContext?.http?.method;
  if (method === "OPTIONS") return { statusCode: 204, headers: CORS };

  if (!INSTANCE_ID) return json(500, { error: "INSTANCE_ID not configured" });

  try {
    // 1. Current state
    const desc = await ec2.send(
      new DescribeInstancesCommand({ InstanceIds: [INSTANCE_ID] })
    );
    const instance = desc.Reservations?.[0]?.Instances?.[0];
    const state = instance?.State?.Name; // pending|running|stopping|stopped|...

    // 2. Stamp / extend the auto-stop deadline
    const wakeUntil = new Date(
      Date.now() + KEEP_ALIVE_MINUTES * 60_000
    ).toISOString();
    await ec2.send(
      new CreateTagsCommand({
        Resources: [INSTANCE_ID],
        Tags: [{ Key: "WakeUntil", Value: wakeUntil }],
      })
    );

    // 3. Start if not already running/pending
    let action = "already_running";
    if (state !== "running" && state !== "pending") {
      await ec2.send(
        new StartInstancesCommand({ InstanceIds: [INSTANCE_ID] })
      );
      action = "starting";
    }

    return json(200, {
      action,
      previousState: state,
      wakeUntil,
      keepAliveMinutes: KEEP_ALIVE_MINUTES,
      // The splash uses this to know roughly how long to wait before polling.
      estimatedReadySeconds: action === "already_running" ? 0 : 180,
    });
  } catch (err) {
    console.error("[wake] error", err);
    return json(500, { error: String(err?.message ?? err) });
  }
};
