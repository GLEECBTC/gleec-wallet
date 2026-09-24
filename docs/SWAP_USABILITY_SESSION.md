# Unified swap — moderated usability session

The prototype's QA left one production gate open: a moderated study with at least five representative wallet users. This is the script for it.

**It passes when:**
- at least four of the five complete each core task unassisted; and
- none misunderstands any of the five money facts below.

## The five money facts

Probe each one after the task that shows it. A single misunderstanding by anyone is a failure to fix before release, whatever the completion rate.

1. **Minimum received:** what "at least" means, and that the expected amount may not arrive.
2. **Destination network:** which network the received asset lands on.
3. **Active recipient:** that the swap sends to their own address, which address that is, and that it cannot be changed here.
4. **Whether they can cancel:** until when, and what is already spent by then (an approval's fee).
5. **Where the funds are:** after a result that is not a clean completion, where the money is now.

## Setup

- **Participants:** five users who hold crypto and have swapped at least once elsewhere. Include at least one who has never used a bridge, and one on a phone.
- **Build:** the release candidate, on a funded test wallet the moderator controls. Use small balances on Arbitrum and Polygon: ETH, USDC and POL. Participants never enter their own seed.
- **Record:** the screen and the voice. The moderator notes the time taken, each hesitation, and the exact words for the five facts.
- **Moderation:** read each task exactly as written. Do not name buttons or screens. If a participant is stuck for two minutes, say "What would you try next?" once. If still stuck, mark the task *assisted* and move on.
- **Length:** 30–40 minutes per participant.

## Tasks

Ask participants to think aloud throughout.

1. **Warm-up.** "Open the swap screen. Tell me what you think it does."
2. **Same network.** "Swap about $5 of ETH for USDC, on Arbitrum."
   - Before they confirm, ask: "How much USDC will you get, at the least?" *(fact 1)* and "Where will it arrive?" *(facts 2 and 3)*
3. **Across networks.** "Move about $5 of your USDC on Polygon to Arbitrum."
   - During the bridge step, ask: "Can you still stop this? What would it cost you?" *(fact 4)*
   - Then: "You need to leave this screen. Go to your wallet, then find this swap again."
4. **An asset that isn't active.** "Swap some USDC for a coin you don't hold yet."
   - Choose it in advance: a supported asset that is inactive on the test wallet.
   - Watch whether they understand the activation step.
5. **Something that can't be swapped.** "Swap GLEEC for PAXG."
   - Ask: "Why can't you? What would you do instead?"
   - Success: they give a reason in their own words and choose another asset.
6. **Comparing.** "Is there a faster way to do the swap in task 3? Would you choose it? Why?"
7. **Recovery.** Show a prepared swap that ended refunded or partially filled, on the moderator's device if the test wallet has none.
   - Ask: "What happened? Where is the money now? What can you do?" *(fact 5)*
8. **Wrap-up.** "What, if anything, worried you? What would you tell a friend about this screen?"

## Scoring

For each participant and task, record: *completed unassisted*, *completed assisted* or *not completed*. Also record whether each of the five facts was understood, and a quote for any misunderstanding.

**Report:**
- per task, how many of the five completed it unassisted (four needed);
- per fact, every misunderstanding verbatim (zero allowed);
- the three most frequent hesitations, each with the screen and the words that caused it.

File each failed gate as an issue against #3507 before release, with its fix, and retest the fix with at least two new participants.
