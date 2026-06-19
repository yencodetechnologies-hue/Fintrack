const cron = require("node-cron");
const moment = require("moment");
const Reminder = require("../models/reminder");
const admin = require("../config/firebase");

cron.schedule("* * * * *", async () => {

  console.log("🔁 Checking reminders...");

  const now = moment()
      .utcOffset("+05:30")
      .format("YYYY-MM-DD HH:mm");

  console.log("NOW:", now);

  try {

    const reminders = await Reminder.find()
        .populate("userId");

    for (let r of reminders) {

      // SKIP PAID
      if (r.status === "paid") {

        console.log(
            `⛔ Paid Reminder Skipped: ${r._id}`
        );

        continue;
      }

      const paymentDate = moment(r.paymentDate);

      for (let item of r.reminders) {

        let notifyDate;

        switch (item.key) {

          case "7_days_before":

            notifyDate =
                paymentDate.clone().subtract(7, "days");

            break;

          case "3_days_before":

            notifyDate =
                paymentDate.clone().subtract(3, "days");

            break;

          case "1_day_before":

            notifyDate =
                paymentDate.clone().subtract(1, "days");

            break;

          case "due_date":

            notifyDate =
                paymentDate.clone();

            break;

          case "1_day_after":

            notifyDate =
                paymentDate.clone().add(1, "days");

            break;

          default:
            continue;
        }

        for (let t of item.times) {

          const fullDateTime = moment(

              notifyDate.format("YYYY-MM-DD")
              + " "
              + t,

              "YYYY-MM-DD HH:mm"

          )
              .utcOffset("+05:30")
              .format("YYYY-MM-DD HH:mm");

          console.log(
              "CHECK:",
              fullDateTime
          );

          // MATCH FOUND

          if (fullDateTime === now) {

            console.log("🔥 MATCH FOUND");

            if (
                !r.userId ||
                !r.userId.fcmTokens ||
                r.userId.fcmTokens.length === 0
            ) {

              console.log("❌ No FCM Tokens");

              continue;
            }

            let sentAny = false;
            for (let token of r.userId.fcmTokens) {

              try {
                const message = `₹${r.amount} payment due for ${r.bankName}`;

                await admin.messaging().send({

                  token: token,

                  notification: {

                    title:
                    "💳 Fintrack Reminder",

                    body:
                    message,
                  },

                  android: {

                    priority: "high",

                    notification: {

                      channelId:
                      "payment_reminder",

                      sound: "default",

                      icon: "ic_launcher",

                      color: "#00D9FF",

                      sticky: false,

                      visibility: "public",

                      notificationPriority:
                      "PRIORITY_MAX",

                      defaultSound: true,

                      defaultVibrateTimings: true,

                      ticker:
                      "Card Payment Alert",

                      tag:
                      "payment-reminder",

                    },
                  },

                  data: {

                    type:
                    "payment_reminder",

                    bankName:
                    r.bankName.toString(),

                    amount:
                    r.amount.toString(),

                    paymentDate:
                    r.paymentDate.toString(),

                    status:
                    r.status.toString(),
                  },
                });

                r.notificationLogs.push({
                  message,
                  sentAt: new Date(),
                });
                sentAny = true;
                console.log(
                    "✅ Notification Sent:",
                    token
                );

              } catch (err) {

                console.log(
                    "❌ Firebase Error:",
                    err.message
                );
              }
            }
            if (sentAny) {
              await r.save();
            }
          }
        }
      }
    }

  } catch (err) {

    console.log(
        "❌ Cron Error:",
        err.message
    );
  }
});