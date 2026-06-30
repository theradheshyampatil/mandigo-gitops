// =============================================================================
// Stop Lambda — runs on an EventBridge cron (every 5 min). Stops the MandiGo
// EC2 instance once the WakeUntil tag (set by the wake Lambda) is in the past.
//
// Safety properties:
//   - If the instance isn't running, do nothing.
//   - If there's NO WakeUntil tag, do nothing (you might be working on it
//     manually — we never stop an untagged running instance).
//   - Only stops when now >= WakeUntil.
// =============================================================================

import {
  EC2Client,
  DescribeInstancesCommand,
  StopInstancesCommand,
} from "@aws-sdk/client-ec2";

const REGION = process.env.AWS_REGION || "ap-south-1";
const INSTANCE_ID = process.env.INSTANCE_ID;

const ec2 = new EC2Client({ region: REGION });

export const handler = async () => {
  if (!INSTANCE_ID) return { ok: false, error: "INSTANCE_ID not configured" };

  const desc = await ec2.send(
    new DescribeInstancesCommand({ InstanceIds: [INSTANCE_ID] })
  );
  const instance = desc.Reservations?.[0]?.Instances?.[0];
  const state = instance?.State?.Name;

  if (state !== "running") {
    return { ok: true, skipped: `instance state is '${state}'` };
  }

  const tag = (instance.Tags || []).find((t) => t.Key === "WakeUntil");
  if (!tag) {
    // No deadline set — assume a human is using it. Leave it alone.
    return { ok: true, skipped: "no WakeUntil tag; not auto-stopping" };
  }

  const wakeUntilMs = Date.parse(tag.Value);
  if (Number.isNaN(wakeUntilMs)) {
    return { ok: true, skipped: `unparseable WakeUntil '${tag.Value}'` };
  }

  if (Date.now() >= wakeUntilMs) {
    await ec2.send(new StopInstancesCommand({ InstanceIds: [INSTANCE_ID] }));
    return { ok: true, stopped: true, wakeUntil: tag.Value };
  }

  return { ok: true, skipped: `WakeUntil in future (${tag.Value})` };
};
