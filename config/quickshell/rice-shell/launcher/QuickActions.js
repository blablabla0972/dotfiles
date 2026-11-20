.pragma library

function calculate(expression) {
    if (expression.length > 512)
        return {error: "Expression is too long"};

    let rest = expression;

    function take(pattern) {
        rest = rest.replace(/^\s+/, "");
        const match = rest.match(pattern);
        if (!match) return "";
        rest = rest.slice(match[0].length);
        return match[0];
    }

    function finite(value) {
        if (!Number.isFinite(value)) throw new Error("Number out of range");
        return value;
    }

    function primary() {
        const sign = take(/^[+-]/);
        if (sign) return sign === "-" ? -primary() : primary();

        if (take(/^\(/)) {
            const value = sum();
            if (!take(/^\)/)) throw new Error("Expected a closing parenthesis");
            return value;
        }

        const number = take(/^(?:\d+(?:\.\d*)?|\.\d+)(?:e[+-]?\d+)?/i);
        if (!number) throw new Error("Expected a number or parenthesis");
        return finite(Number(number));
    }

    function product() {
        let value = primary();
        for (let op; (op = take(/^[*/]/)); ) {
            const next = primary();
            if (op === "/" && next === 0) throw new Error("Cannot divide by zero");
            value = finite(op === "*" ? value * next : value / next);
        }
        return value;
    }

    function sum() {
        let value = product();
        for (let op; (op = take(/^[+-]/)); ) {
            const next = product();
            value = finite(op === "+" ? value + next : value - next);
        }
        return value;
    }

    try {
        if (!rest.trim()) return {error: "Enter an expression"};
        const value = sum();
        if (rest.trim()) return {error: "Unexpected input"};
        // Hide floating-point noise while retaining the digits of safe integers.
        const rounded = Number(value.toPrecision(15));
        return {value: String(Number.isSafeInteger(value) || !Number.isFinite(rounded) ? value : rounded)};
    } catch (error) {
        return {error: error.message};
    }
}

const actions = [
    {action: "dnd", name: "Toggle Do Not Disturb", comment: "DND · Notifications"},
    {action: "volume-up", name: "Volume up", comment: "+5 percentage points"},
    {action: "volume-down", name: "Volume down", comment: "-5 percentage points"},
    {action: "brightness-up", name: "Brightness up", comment: "+10 percentage points"},
    {action: "brightness-down", name: "Brightness down", comment: "-10 percentage points"},
    {action: "system", name: "Open System", comment: "Control Center"},
    {action: "power", name: "Open Power", comment: "Control Center · Battery and profiles"},
    {action: "reload", name: "Reload Rice Shell", comment: "Apply shell configuration"}
];

function findActions(query) {
    const terms = query.trim().toLowerCase().split(/\s+/);
    return actions.filter(item => terms.every(term =>
        (item.name + " " + item.comment).toLowerCase().includes(term)));
}
