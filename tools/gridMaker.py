import tftest
import json
import collections

gridInputs={}
with open('gridInputs.json', "r") as f:
    gridInputs=json.load(f)

print(dict.keys(gridInputs))

templateToTest=gridInputs["templateToTest"]
dirToTest=f"../{templateToTest}/terraform/{templateToTest}"
outputCsv=f"{templateToTest}_builds.csv"

# These variables are intentionally copied here to make necesary inputs more clear.
tfVars = gridInputs["tfVars"]
# Keys must match the actual variables in TF!
inputLookups= gridInputs["inputLookups"]
resourcesToPrint= gridInputs["resourcesToPrint"]
# Could be abstracted to look at outputs as well. Not currently implemented.

inputNames=collections.deque(dict.keys(inputLookups))

tf = tftest.TerraformTest(
    tfdir=dirToTest)

tf.init()

currentInputVals=[]
def recursiveInput(remainingKeys):
    if (len(remainingKeys) == 0):
        # do the output
        printPlanLine()
        return

    localKey=remainingKeys.popleft()
    for inputVal in inputLookups[localKey]:
        print(f"New {localKey} value: {inputVal}")
        currentInputVals.append(inputVal)
        tfVars[localKey] = inputVal
        recursiveInput(remainingKeys)
        currentInputVals.pop()
    remainingKeys.appendleft(localKey)

def printPlanLine():
    thePlan=tf.plan(output=True, tf_vars=tfVars)
    outline = ""
    for inputVal in currentInputVals:
        outline = outline + f"{inputVal}, "

    for output in resourcesToPrint:
        toAdd="n/a"
        if ( output['resourceKey'] in thePlan.resources ) and ( output['param'] in thePlan.resources[output['resourceKey']]["values"]):
            toAdd=thePlan.resources[output['resourceKey']]["values"][output['param']]
        outline = outline + f"{toAdd}, "


    with open(outputCsv, "a") as file1:
        file1.write(f"{outline} \n")

def makeHeader():
    header=""
    inputNames=collections.deque(dict.keys(inputLookups))

    for inputs in inputNames:
        header = header + f"{inputs}, "

    for output in resourcesToPrint:
        header = header + f"{output['name']}, "

    print(header)
    with open(outputCsv, "w") as file1:
        file1.write(f"{header} \n")



makeHeader()
recursiveInput(inputNames)



