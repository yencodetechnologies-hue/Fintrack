const yahooAuthService = require("../services/yahooAuthService");

async function getConnectUrl(req, res) {
  try {
    const { userId, useFull } = req.query;
    console.log(`📥 [Yahoo Controller] GET /yahoo-connect-url requested for userId: ${userId}, useFull: ${useFull}`);
    if (!userId) {
      console.warn("⚠️ [Yahoo Controller] Missing userId query parameter");
      return res.status(400).json({ success: false, message: "userId query param required" });
    }
    const authUrl = yahooAuthService.getConnectUrl(userId, useFull === "true");
    console.log(`📤 [Yahoo Controller] Responding with connect authUrl`);
    return res.json({ success: true, authUrl });
  } catch (err) {
    console.error("🔴 [Yahoo Controller] Error in getConnectUrl:", err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
}

async function handleCallback(req, res) {
  const { code, state, error, error_description } = req.query;
  console.log(`📥 [Yahoo Controller] GET /oauth/callback received. state: ${state}, code length: ${code ? code.length : 0}`);

  if (error) {
    console.error("🔴 [Yahoo Controller] Yahoo OAuth Callback Error:", error, error_description);
    return res.send(`
      <!DOCTYPE html>
      <html>
      <head><title>Yahoo Auth Failed</title></head>
      <body style="font-family:sans-serif; text-align:center; padding:50px; background:#F6F4EB;">
        <h2 style="color:#B8452D;">Authentication Failed</h2>
        <p>${error_description || error}</p>
        <p>You may close this browser window and return to Q Fin.</p>
      </body>
      </html>
    `);
  }

  if (!code || !state) {
    console.warn("⚠️ [Yahoo Controller] OAuth Callback missing code or state");
    return res.status(400).send("Missing code or state in OAuth callback.");
  }

  try {
    const result = await yahooAuthService.handleOAuthCallback(code, state);
    console.log(`✅ [Yahoo Controller] Callback processed successfully for Yahoo email: ${result.yahooEmail}`);
    return res.send(`
      <!DOCTYPE html>
      <html>
      <head>
        <title>Yahoo Connected!</title>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #0F261C; color: #F6F4EB; text-align: center; padding: 40px 20px; }
          .card { background: #183B2B; border: 1px solid #D4AF37; border-radius: 20px; padding: 30px; max-width: 400px; margin: 0 auto; box-shadow: 0 10px 30px rgba(0,0,0,0.5); }
          h1 { color: #D4AF37; font-size: 24px; margin-bottom: 10px; }
          p { font-size: 15px; color: #C7D3C3; line-height: 1.5; }
          .badge { display: inline-block; background: rgba(212,175,55,0.15); border: 1px solid #D4AF37; color: #D4AF37; padding: 6px 16px; border-radius: 20px; font-weight: bold; margin-top: 15px; }
        </style>
      </head>
      <body>
        <div class="card">
          <h1>🎉 Yahoo Connected!</h1>
          <p>Your Yahoo Mail account <strong>${result.yahooEmail || ""}</strong> has been linked successfully.</p>
          <div class="badge">Return to Q Fin App</div>
        </div>
        <script>
          setTimeout(() => {
            window.location.href = "fintrack://oauth/success";
          }, 1500);
        </script>
      </body>
      </html>
    `);
  } catch (err) {
    console.error("🔴 [Yahoo Controller] OAuth Callback Exception:", err.message);
    return res.status(500).send(`
      <!DOCTYPE html>
      <html>
      <head><title>Connection Error</title></head>
      <body style="font-family:sans-serif; text-align:center; padding:50px; background:#F6F4EB;">
        <h2 style="color:#B8452D;">Connection Failed</h2>
        <p>${err.message}</p>
      </body>
      </html>
    `);
  }
}

async function getStatus(req, res) {
  try {
    const { userId } = req.params;
    console.log(`📥 [Yahoo Controller] GET /yahoo-status/${userId}`);
    const status = await yahooAuthService.getYahooStatus(userId);
    return res.json({ success: true, ...status });
  } catch (err) {
    console.error("🔴 [Yahoo Controller] Error in getStatus:", err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
}

async function disconnect(req, res) {
  try {
    const { userId } = req.body;
    console.log(`📥 [Yahoo Controller] POST /yahoo-disconnect for userId: ${userId}`);
    if (!userId) {
      return res.status(400).json({ success: false, message: "userId is required" });
    }
    const result = await yahooAuthService.disconnectYahoo(userId);
    return res.json(result);
  } catch (err) {
    console.error("🔴 [Yahoo Controller] Error in disconnect:", err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
}

async function connectAppPassword(req, res) {
  try {
    const { userId, yahooEmail, appPassword } = req.body;
    console.log(`📥 [Yahoo Controller] POST /yahoo-connect-app-password for ${yahooEmail}`);
    if (!userId || !yahooEmail || !appPassword) {
      return res.status(400).json({ success: false, message: "userId, yahooEmail, and appPassword are required" });
    }
    const result = await yahooAuthService.connectYahooWithAppPassword(userId, yahooEmail, appPassword);
    return res.json(result);
  } catch (err) {
    console.error("🔴 [Yahoo Controller] Error in connectAppPassword:", err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
}

module.exports = {
  getConnectUrl,
  handleCallback,
  getStatus,
  disconnect,
  connectAppPassword,
};
