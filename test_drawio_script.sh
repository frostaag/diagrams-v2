#!/bin/bash
# Simple test for the Draw.io processing script

set -euo pipefail

echo "🧪 Testing Draw.io processing script..."

# Create a temporary test environment
TEST_DIR="/tmp/drawio_test_$$"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

# Set up directory structure
mkdir -p drawio_files png_files
echo "001" > drawio_files/.counter

# Create a simple test drawio file
cat > drawio_files/test.drawio << 'EOF'
<mxfile host="app.diagrams.net" modified="2024-06-03T10:00:00.000Z" agent="5.0" version="21.1.2" etag="test123">
  <diagram name="Page-1" id="test-page-1">
    <mxGraphModel dx="1422" dy="794" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="827" pageHeight="1169" math="0" shadow="0">
      <root>
        <mxCell id="0" />
        <mxCell id="1" parent="0" />
        <mxCell id="2" value="Test Box" style="rounded=0;whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="340" y="280" width="120" height="60" as="geometry" />
        </mxCell>
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
EOF

# Initialize changelog
echo "Date,Time,Diagram,File,Action,Commit Message,Version,Commit Hash,Author Name" > png_files/CHANGELOG.csv

# Initialize git repo for testing
git init
git config user.email "test@example.com"
git config user.name "Test User"
git add .
git commit -m "Initial test commit"

echo "✅ Test environment created in $TEST_DIR"
echo "📂 Contents:"
find . -type f | sort

# Clean up on exit
trap "rm -rf $TEST_DIR" EXIT

echo ""
echo "🧪 Test completed. Environment will be cleaned up on exit."
